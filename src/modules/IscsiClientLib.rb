# encoding: utf-8

# |***************************************************************************
# |
# | Copyright (c) [2012] Novell, Inc.
# | All Rights Reserved.
# |
# | This program is free software; you can redistribute it and/or
# | modify it under the terms of version 2 of the GNU General Public License as
# | published by the Free Software Foundation.
# |
# | This program is distributed in the hope that it will be useful,
# | but WITHOUT ANY WARRANTY; without even the implied warranty of
# | MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# | GNU General Public License for more details.
# |
# | You should have received a copy of the GNU General Public License
# | along with this program; if not, contact Novell, Inc.
# |
# | To contact Novell about this file by physical or electronic mail,
# | you may find current contact information at www.novell.com
# |
# |***************************************************************************
require "yast"
require "yast2/systemd/socket"
require "ipaddr"

require "shellwords"

module Yast
  class IscsiClientLibClass < Module
    include Yast::Logger

    Yast.import "Arch"

    OFFLOAD_SCRIPT = "/sbin/iscsi_offload".freeze

    def main
      textdomain "iscsi-client"

      Yast.import "Service"
      Yast.import "Popup"
      Yast.import "Hostname"
      Yast.import "Stage"
      Yast.import "ModuleLoading"
      Yast.import "Mode"
      Yast.import "String"
      Yast.import "Arch"

      @sessions = []
      @discovered = []
      @targets = []
      @currentRecord = []
      @iface_file = {}
      @iface_eth = []

      # status of iscsi.service
      @iscsi_service_stat = false
      # status of iscsid.socket
      @iscsid_socket_stat = false
      # status of iscsiuio.socket
      @iscsiuio_socket_stat = false
      # main configuration file (/etc/iscsi/iscsid.conf)
      @config = {}
      # iBFT (iSCSI Boot Firmware Table)
      @ibft = nil
      # InitiatorName file (/etc/iscsi/initiatorname.iscsi)
      @initiatorname = ""
      # map used for autoYaST
      @ay_settings = nil
      # interface type for hardware offloading
      @offload_card = "default"

      @offload = [
        ["default", _("default (Software)"), [], []],
        ["all", _("all"), [], []],
        ["bnx2", "bnx2/bnx2i/bnx2x", ["bnx2", "bnx2i", "bnx2x"], ["bnx2i"]],
        ["cxgb3", "cxgb3/cxgb3i", ["cxgb3", "cxgb3i"], ["cxgb3i"]],
        ["enic", "enic/cnic/fnic", ["enic", "fnic"], ["fnic"]],
        [
          "qla4xxx",
          "qla3xxx/qla4xxx",
          ["qla4xxx", "qla3xxx", "qlcnic"],
          ["qla4xxx"]
        ],
        ["be2net", "be2net/be2iscsi", ["be2net", "be2iscsi"], ["be2iscsi"]]
      ]

      @offload_valid = nil

      @iscsid_socket = nil
      @iscsiuio_socket = nil
    end

    def socketActive?(socket)
      if socket
        socket.active?
      else
        log.error "socket not available"
        false
      end
    end

    def socketStart(socket)
      if socket
        socket.start
      else
        log.error "socket not available"
        false
      end
    end

    def socketStop(socket)
      if socket
        socket.stop
      else
        log.error "socket not available"
        false
      end
    end

    def socketEnabled?(socket)
      if socket
        socket.enabled?
      else
        log.error "socket not available"
        false
      end
    end

    def socketDisabled?(socket)
      if socket
        socket.disabled?
      else
        log.error "socket not available"
        false
      end
    end

    def socketEnable(socket)
      if socket
        socket.enable
      else
        log.error "socket not available"
        false
      end
    end

    def socketDisable(socket)
      if socket
        socket.disable
      else
        log.error "socket not available"
        false
      end
    end

    def GetOffloadCard
      @offload_card
    end

    def SetOffloadCard(new_card)
      Builtins.y2milestone("SetOffloadCard:%1 cur:%2", new_card, @offload_card)
      if new_card != @offload_card
        @offload_card = new_card
        CallConfigScript() if new_card != "default"
      end

      nil
    end

    # Create and return complete iscsciadm command by adding the string
    # argument as options. If allowed, write the command to y2log file.
    #
    # @param  [String] params	options for iscsiadm command
    # @param  [Boolean] do_log  write command to y2log?
    # @return [String] complete command
    #
    def GetAdmCmd(params, do_log = true)
      ret = "LC_ALL=POSIX /sbin/iscsiadm"
      ret = Ops.add(Ops.add(ret, " "), params)
      Builtins.y2milestone("GetAdmCmd: #{ret}") if do_log
      ret
    end

    def hidePassword(orig)
      orig = deep_copy(orig)
      hidden = {}
      Builtins.foreach(orig) do |key, value|
        value = "*****" if Builtins.issubstring(key, "PASS")
        Ops.set(hidden, key, value)
      end
      deep_copy(hidden)
    end

    # Look for iSCSI boot firmware table (available only on special hardware/netcards)
    #
    # @return [String] stdout of command 'iscsiadm -m fw' (--mode fw)
    #
    def getFirmwareInfo
      bios_info = SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m fw"))

      bios_info["stdout"] || ""
    end

    # Takes the output of 'iscsiadm' either in 'node', 'session' or 'fw' mode, i.e.
    # output where info is seperated by '=', like
    # iface.transport_name = tcp
    # iface.hwaddress = 42:52:54:00:8b:6a
    # iface.bootproto = DHCP
    #
    #  @param [String]   stdout (where info is seperated by '=') of iscsiadm command
    #  @return [Hash]    command output converted to hash
    #
    def nodeInfoToMap(stdout)
      retval = {}
      return retval if stdout.empty?

      stdout.lines.each do |row|
        key, val = row.split("=")

        key = key.to_s.strip
        retval[key] = val.to_s.strip if !key.empty?
      end

      retval
    end

    # Get iBFT (iSCSI boot firmware table) info
    #
    # @return [Hash] iBFT data converted to a hash (passwords are hidden)
    #
    def getiBFT
      if @ibft == nil
        @ibft = {}

        if !Arch.i386 && !Arch.x86_64
          log.info "Because architecture #{Arch.arch_short} is different from x86, not using iBFT"
          return @ibft
        end
        ret = SCR.Execute(path(".target.bash_output"),
          "/usr/bin/lsmod | /usr/bin/grep -q iscsi_ibft || /usr/sbin/modprobe iscsi_ibft")
        log.info "check and modprobe iscsi_ibft: #{ret}"

        @ibft = nodeInfoToMap(getFirmwareInfo)
      end

      log.info "iBFT: #{hidePassword(@ibft)}"
      @ibft
    end

    # get accessor for service status
    def GetStartService
      status_d = socketEnabled?(@iscsid_socket)
      status_uio = socketEnabled?(@iscsiuio_socket)
      status = Service.Enabled("iscsi")
      log.info "Start at boot enabled for iscsid.socket: #{status_d}, iscsi: #{status}, iscsiuio.socket: #{status_uio}"
      return status_d && status && status_uio
    end

    # set accessor for service status
    def SetStartService(status)
      log.info "Set start at boot for iscsid.socket, iscsiuio.socket and iscsi.service to #{status}"
      if status == true
        Service.Enable("iscsi")
        socketEnable(@iscsid_socket)
        socketEnable(@iscsiuio_socket)
      else
        Service.Disable("iscsi")
        socketDisable(@iscsid_socket)
        socketDisable(@iscsiuio_socket)
      end

      nil
    end

    # read configuration file
    def getConfig
      # use cache if available
      if Builtins.size(@config) == 0
        @config = Convert.convert(
          SCR.Read(path(".etc.iscsid.all")),
          :from => "any",
          :to   => "map <string, any>"
        )
        Builtins.y2debug("read config %1", @config)
      end
      Ops.get_list(@config, "value", [])
    end

    def setConfig(new_config)
      new_config = deep_copy(new_config)
      Ops.set(@config, "value", new_config)

      nil
    end

    # do we use iSNS for targets?
    def useISNS
      isns_info = { "use" => false, "address" => "", "port" => "3205" }
      # validateISNS checks for not empty address and port,
      # storeISNS adds values to config
      Builtins.foreach(getConfig) do |row|
        if row["name"] == "isns.address"
          isns_info["address"] = row["value"]
          isns_info["use"] = true
        elsif row["name"] == "isns.port"
          isns_info["port"] = row["value"]
        end
      end
      isns_info
    end

    # write temporary changed old config
    def oldConfig
      Builtins.y2milestone("Store temporary config %1", @config)
      SCR.Write(path(".etc.iscsid.all"), @config)
      SCR.Write(path(".etc.iscsid"), nil)

      nil
    end

    def getNode
      cmdline = GetAdmCmd(
        Builtins.sformat(
          "-S -m node -I %3 -T %1 -p %2",
          Ops.get(@currentRecord, 1, "").shellescape,
          Ops.get(@currentRecord, 0, "").shellescape,
          Ops.get(@currentRecord, 2, "default").shellescape
        )
      )
      cmd = SCR.Execute(path(".target.bash_output"), cmdline)
      return {} if Ops.get_integer(cmd, "exit", 0) != 0
      auth = {}
      Builtins.foreach(
        Builtins.splitstring(Ops.get_string(cmd, "stdout", ""), "\n")
      ) do |row|
        key = Ops.get(Builtins.splitstring(row, " = "), 0, "")
        val = Ops.get(Builtins.splitstring(row, " = "), 3, "")
        val = "" if val == "<empty>"
        case key
        when "node.session.auth.authmethod"
          Ops.set(auth, "authmethod", val)
        when "node.session.auth.username"
          Ops.set(auth, "username", val)
        when "node.session.auth.password"
          Ops.set(auth, "password", val)
        when "node.session.auth.username_in"
          Ops.set(auth, "username_in", val)
        when "node.session.auth.password_in"
          Ops.set(auth, "password_in", val)
        end
      end
      deep_copy(auth)
    end

    # create map from given map in format needed by ini-agent
    def createMap(old_map, comments)
      old_map = deep_copy(old_map)
      comments = deep_copy(comments)
      comment = ""
      Builtins.foreach(comments) do |row|
        comment = Builtins.sformat("%1%2", comment, row)
      end
      {
        "name"    => Ops.get_string(old_map, "KEY", ""),
        "value"   => Ops.get_string(old_map, "VALUE", ""),
        "kind"    => "value",
        "type"    => 1,
        "comment" => comment
      }
    end

    # add or modify given map
    def setOrAdd(old_list, key, value)
      old_list = deep_copy(old_list)
      new_list = []
      found = false
      Builtins.foreach(old_list) do |row|
        if Ops.get_string(row, "name", "") == key
          found = true
          Ops.set(row, "value", value)
        end
        new_list = Builtins.add(new_list, row)
      end
      if !found
        new_list = Builtins.add(
          new_list,
          createMap({ "KEY" => key, "VALUE" => value }, [])
        )
      end
      deep_copy(new_list)
    end

    # delete record with given key
    def delete(old_list, key)
      old_list = deep_copy(old_list)
      Builtins.y2milestone("Delete record for %1", key)
      new_list = []
      Builtins.foreach(old_list) do |row|
        if Ops.get_string(row, "name", "") != key
          new_list = Builtins.add(new_list, row)
        end
      end
      deep_copy(new_list)
    end

    # temporary change config for discovery authentication
    def saveConfig(user_in, pass_in, user_out, pass_out)
      Builtins.y2milestone("Save config")
      tmp_conf = deep_copy(@config)
      tmp_val = Ops.get_list(tmp_conf, "value", [])

      if (specified = !user_in.empty? && !pass_in.empty?)
        tmp_val = setOrAdd(
          tmp_val,
          "discovery.sendtargets.auth.authmethod",
          "CHAP"
        )
        tmp_val = setOrAdd(
          tmp_val,
          "discovery.sendtargets.auth.username_in",
          user_in
        )
        tmp_val = setOrAdd(
          tmp_val,
          "discovery.sendtargets.auth.password_in",
          pass_in
        )
      else
        tmp_val = delete(tmp_val, "discovery.sendtargets.auth.username_in")
        tmp_val = delete(tmp_val, "discovery.sendtargets.auth.password_in")
      end

      if (specified = !user_out.empty? && !pass_out.empty?)
        tmp_val = setOrAdd(
          tmp_val,
          "discovery.sendtargets.auth.authmethod",
          "CHAP"
        )
        tmp_val = setOrAdd(
          tmp_val,
          "discovery.sendtargets.auth.username",
          user_out
        )
        tmp_val = setOrAdd(
          tmp_val,
          "discovery.sendtargets.auth.password",
          pass_out
        )
      else
        tmp_val = delete(tmp_val, "discovery.sendtargets.auth.username")
        tmp_val = delete(tmp_val, "discovery.sendtargets.auth.password")
      end

      if user_in.empty? && user_out.empty?
        tmp_val = delete(tmp_val, "discovery.sendtargets.auth.authmethod")
      end

      Ops.set(tmp_conf, "value", tmp_val)
      SCR.Write(path(".etc.iscsid.all"), tmp_conf)
      SCR.Write(path(".etc.iscsid"), nil)

      nil
    end

    # Called for data (output) of commands:
    #  iscsiadm -m node -P 1
    #  iscsiadm -m session -P 1
    def ScanDiscovered(data)
      data = deep_copy(data)
      ret = []
      target = ""
      portal = ""
      iface = ""
      Builtins.y2milestone("Got data: %1", data)

      Builtins.foreach(data) do |row|
        row = Builtins.substring(row, Builtins.findfirstnotof(row, "\t "), 999)
        if Builtins.search(row, "Target:") != nil
          target = Ops.get(Builtins.splitstring(row, " "), 1, "")
        elsif Builtins.search(row, "Portal:") != nil
          if Builtins.search(row, "Current Portal:") != nil
            portal = Ops.get(Builtins.splitstring(row, " "), 2, "")
          elsif Builtins.search(row, "Persistent Portal:") != nil
            # 'Persistent Portal' overwrites current (is used for login)
            portal = Ops.get(Builtins.splitstring(row, " "), 2, "")
          else
            # read 'Portal' (from output of -m node)
            portal = Ops.get(Builtins.splitstring(row, " "), 1, "")
          end
          pos = Builtins.search(portal, ",")
          portal = Builtins.substring(portal, 0, pos) if pos != nil
        elsif Builtins.search(row, "Iface Name:") != nil
          iface = Ops.get(Builtins.splitstring(row, " "), 2, "")
          iface = Ops.get(@iface_file, iface, iface)
          # don't add Scope:Link IPv6 address
          if !portal.start_with?("[fe80:")
            ret = ret << "#{portal} #{target} #{iface}"
          end
        end
      end
      Builtins.y2milestone("ScanDiscovered ret:%1", ret)
      deep_copy(ret)
    end

    # get all discovered targets
    def getDiscovered
      @discovered = []
      retcode = SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m node -P 1"))
      if Builtins.size(Ops.get_string(retcode, "stderr", "")) == 0
        @discovered = ScanDiscovered(
          Builtins.splitstring(Ops.get_string(retcode, "stdout", ""), "\n")
        )
      end
      deep_copy(@discovered)
    end

    def start_services_initial
      # start service 'iscsiuio' and daemon 'iscsid'
      Service.Start("iscsiuio")
      start_iscsid_initial
    end

    def restart_iscsid_initial
      retcode = SCR.Execute(path(".target.bash"), "/usr/bin/pgrep iscsid")
      Service.Stop("iscsid") if retcode == 0
      start_iscsid_initial
    end

    def start_iscsid_initial
      SCR.Execute(path(".target.bash"), "/usr/bin/pgrep iscsid || /sbin/iscsid")
      10.times do |i|
        Builtins.sleep(1 * 1000)
        cmd = SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m session"))
        Builtins.y2internal(
          "iteration %1, retcode %2",
          i,
          Ops.get_integer(cmd, "exit", -1)
        )
        if Ops.get_integer(cmd, "exit", -1) == 0
          Builtins.y2internal("Good response from daemon, exit.")
          break
        end
      end

      nil
    end

    # get all connected targets
    def readSessions
      Builtins.y2milestone("reading current settings")
      retcode = SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m session -P 1"))
      @sessions = ScanDiscovered(
        Builtins.splitstring(Ops.get_string(retcode, "stdout", ""), "\n")
      )
      Builtins.y2milestone(
        "Return list from iscsiadm -m session: %1",
        @sessions
      )
      true
    end

    # write InitiatorName, create backup from previous if needed
    def writeInitiatorName(new_value)
      ret = true
      file = "/etc/iscsi/initiatorname.iscsi"
      dir = "/etc/iscsi"
      if Convert.to_map(SCR.Read(path(".target.stat"), dir)) == {}
        SCR.Execute(path(".target.mkdir"), dir)
        Builtins.y2milestone(
          "writeInitiatorName dir:%1",
          SCR.Read(path(".target.stat"), dir)
        )
      end
      if Ops.greater_than(
        Ops.get_integer(
          Convert.convert(
            SCR.Read(path(".target.lstat"), file),
            :from => "any",
            :to   => "map <string, any>"
          ),
          "size",
          0
        ),
        0
      )
        Builtins.y2milestone("%1 file exists, create backup", file)
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("/usr/bin/mv %1 /etc/iscsi/initiatorname.yastbackup", file.shellescape)
        )
      end
      ret = SCR.Write(
        path(".target.string"),
        [file, 384],
        Builtins.sformat("InitiatorName=%1\n", new_value)
      )
      if ret
        @initiatorname = new_value
        Builtins.y2milestone("Initiatorname %1 written", @initiatorname)
      end
      # reload service when initiatorname is changed to re-read new value (bnc#482429)
      # SLES12: restart the daemon (reload not supported in iscsid.service)
      if Stage.initial
        restart_iscsid_initial
      else
        Service.Restart("iscsid")
      end
      ret
    end

    def getReverseDomainName
      host_fq = Hostname.SplitFQ(
        Ops.get_string(
          SCR.Execute(path(".target.bash_output"), "/usr/bin/hostname -f | /usr/bin/tr -d '\n'"),
          "stdout",
          ""
        )
      )
      Builtins.y2internal("hostfw%1", host_fq)
      domain = ""

      Builtins.foreach(
        Builtins.splitstring(Ops.get(host_fq, 1, "example.com"), ".")
      ) do |item|
        Builtins.y2internal("item %1", item)
        domain = Builtins.size(domain) == 0 ?
          item :
          Builtins.sformat("%1.%2", item, domain)
      end

      Builtins.y2milestone("domain %1", domain)
      domain
    end

    # check initiatorname if exist, if no - create it
    def checkInitiatorName
      ret = true
      file = "/etc/iscsi/initiatorname.iscsi"
      name_from_bios = getiBFT["iface.initiatorname"] || ""
      # if (size((map<string, any>)SCR::Read (.target.lstat, file)) == 0 || ((map<string, any>)SCR::Read (.target.lstat, file))["size"]:0==0){
      @initiatorname = Ops.get_string(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat(
            "/usr/bin/grep -v '^#' %1 | /usr/bin/grep InitiatorName | /usr/bin/cut -d'=' -f2 | /usr/bin/tr -d '\n'",
            file.shellescape
          )
        ),
        "stdout",
        ""
      )
      # }
      if Builtins.size(@initiatorname) == 0
        if Ops.greater_than(Builtins.size(name_from_bios), 0)
          Builtins.y2milestone(
            "%1 is empty or doesnt exists - replace with name stored in iBFT",
            file
          )
          @initiatorname = name_from_bios
        else
          Builtins.y2milestone("InitiatorName does not exist - generate it")
          output = SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "/sbin/iscsi-iname -p iqn.%1.%2:01 | tr -d '\n'",
              "`date +%Y-%m`",
              getReverseDomainName.shellescape
            ),
            {}
          )
          if Builtins.size(Ops.get_string(output, "stderr", "")) == 0
            @initiatorname = Ops.get_string(output, "stdout", "")
          else
            ret = false
          end
        end
        ret = writeInitiatorName(@initiatorname)
      else
        Builtins.y2milestone(
          "checkInitiatorName initiatorname=%1",
          @initiatorname
        )
        if Ops.greater_than(Builtins.size(name_from_bios), 0) &&
            name_from_bios != @initiatorname
          Popup.Warning(
            _(
              "InitiatorName from iBFT and from <tt>/etc/iscsi/initiatorname.iscsi</tt>\n" \
                "differ. The old initiator name will be replaced by the value of iBFT and a \n" \
                "backup created. If you want to use a different initiator name, change it \n" \
                "in the BIOS.\n"
            )
          )
          Builtins.y2milestone(
            "replacing old name %1 by name %2 from iBFT",
            @initiatorname,
            name_from_bios
          )
          @initiatorname = name_from_bios
          ret = writeInitiatorName(@initiatorname)
        end
      end
      ret
    end

    # delete deiscovered target from database
    def deleteRecord
      ret = true
      Builtins.y2milestone("Delete record %1", @currentRecord)

      retcode = SCR.Execute(
        path(".target.bash_output"),
        GetAdmCmd(
          Builtins.sformat(
            "-m node -I %3 -T %1 -p %2 --logout",
            Ops.get(@currentRecord, 1, "").shellescape,
            Ops.get(@currentRecord, 0, "").shellescape,
            Ops.get(@currentRecord, 2, "default").shellescape
          )
        )
      )
      if Ops.greater_than(
        Builtins.size(Ops.get_string(retcode, "stderr", "")),
        0
      )
        return false
      end

      readSessions
      ret
    end

    # Get info about current iSCSI node
    #
    # @return [Hash]    stdout of 'iscsiadm -m node -I <iface> -T <target> -p <ip>'
    #                   converted to a hash
    def getCurrentNodeValues
      ret = SCR.Execute(path(".target.bash_output"),
        GetAdmCmd("-m node -I #{(@currentRecord[2] || "default").shellescape} -T #{(@currentRecord[1] || "").shellescape} -p #{(@currentRecord[0] || "").shellescape}"))
      return {} if ret["exit"] != 0

      nodeInfoToMap(ret["stdout"] || "")
    end

    # Check whether iSCSI nodes are equal
    #
    # @param   [Hash]    iSCSI node values as hash
    # @param   [Hash]    iSCSI node values as hash
    #
    # @return  [Bool]    nodes are equal?
    #
    def equalNodes?(n1, n2)
      return false if n1.empty? || n2.empty?

      # we're going to modify one key...
      n1 = n1.dup
      n2 = n2.dup

      # if unset, use default from /etc/iscsi/initiatorname.iscsi
      n1["iface.initiatorname"] = @initiatorname if n1["iface.initiatorname"] == "<empty>"
      n2["iface.initiatorname"] = @initiatorname if n2["iface.initiatorname"] == "<empty>"

      keys = [
        "iface.transport_name",
        "iface.initiatorname",
        "node.name",
        "node.conn[0].address"
      ]

      keys.all? { |key| n1[key] == n2[key] }
    end

    # Checks whether iSCSI session (values provided as hash) is iBFT session
    #
    # @param  [Hash]      iSCSI node values as hash
    # @return [Bool]      is iSCSI session booted from firmware?
    #
    def iBFT?(node_info)
      return equalNodes?(getiBFT, node_info)
    end

    # Get (manual/onboot/automatic) status of target connection
    #
    # @return [String]   startup status of the iSCSI node
    #
    def getStartupStatus
      log.info "Getting status of record #{@currentRecord}"
      curr_node = getCurrentNodeValues

      if iBFT?(curr_node)
        # always show status "onboot" for iBFT (startup value from node doesn't matter)
        log.info "Startup status for iBFT is always onboot"
        return "onboot"
      end
      status = curr_node["node.conn[0].startup"] || ""

      if Arch.s390 && status == "onboot"
        log.info "Startup status on S/390 changed from onboot to automatic"
        return "automatic"
      end

      log.info "Startup status for #{@currentRecord} is #{status}"

      status
    end

    # update authentication value
    def setValue(name, value)
      rec = @currentRecord
      Builtins.y2milestone("set %1  for record %2", name, rec)

      log = !name.include?("password")
      cmd = "-m node -I #{(rec[2] || "default").shellescape} -T #{(rec[1] || "").shellescape} -p #{(rec[0] || "").shellescape} --op=update --name=#{name.shellescape}"

      command = GetAdmCmd("#{cmd} --value=#{value.shellescape}", log)
      if !log
        value = "*****" if !value.empty?
        Builtins.y2milestone("AdmCmd:LC_ALL=POSIX iscsiadm #{cmd} --value=#{value}")
      end

      ret = true
      retcode = SCR.Execute(path(".target.bash_output"), command)
      if Ops.greater_than(
        Builtins.size(Ops.get_string(retcode, "stderr", "")),
        0
      )
        Builtins.y2error("%1", Ops.get_string(retcode, "stderr", ""))
        ret = false
      end
      Builtins.y2milestone("return value %1", ret)
      ret
    end

    # check whether two given IP addresses (including ports) are equal
    def ipEqual?(session_ip, current_ip)
      return false if !session_ip || !current_ip
      return false if session_ip.empty? || current_ip.empty?

      if !session_ip.start_with?("[") && !current_ip.start_with?("[")
        # both IPv4 - compare directly
        return session_ip == current_ip
      elsif session_ip.start_with?("[") && current_ip.start_with?("[")
        # both IPv6 - compare IPv6 and port separately
        ip_port_regex = /\[([:\w]+)\](:(\d+))?/

        if match_data = session_ip.match(ip_port_regex)
          s_ip = IPAddr.new(match_data[1] || "")
          s_port = match_data[3] || ""
        else
          Builtins.y2error("Session IP %1 not matching", session_ip)
          return false
        end
        if match_data = current_ip.match(ip_port_regex)
          c_ip = IPAddr.new(match_data[1] || "")
          c_port = match_data[3] || ""
        else
          Builtins.y2error("Current IP %1 not matching", current_ip)
          return false
        end
        return (s_ip == c_ip) && (s_port == c_port)
      else
        # comparing IPv4 and IPv6
        return false
      end

    rescue ArgumentError => e
      Builtins.y2error("Invalid IP address, error: %1", e.to_s)
      false
    end

    # check if given target is connected
    def connected(check_ip)
      Builtins.y2internal(
        "check connected status for %1 with IP check:%2",
        @currentRecord,
        check_ip
      )
      ret = false
      Builtins.foreach(@sessions) do |row|
        ip_ok = true
        list_row = Builtins.splitstring(row, " ")
        Builtins.y2milestone("Session row: %1", list_row)
        if check_ip
          session_ip = Ops.get(
            Builtins.splitstring(Ops.get(list_row, 0, ""), ","),
            0, ""
          )
          current_ip = Ops.get(
            Builtins.splitstring(Ops.get(@currentRecord, 0, ""), ","),
            0, ""
          )
          ip_ok = ipEqual?(session_ip, current_ip)
        end

        if Ops.get(list_row, 1, "") == Ops.get(@currentRecord, 1, "") &&
            Ops.get(list_row, 2, "") == Ops.get(@currentRecord, 2, "") &&
            ip_ok
          ret = true
          raise Break
        end
      end
      ret
    end

    # change startup status (manual/onboot) for target
    def setStartupStatus(status)
      Builtins.y2milestone(
        "Set startup status for %1 to %2",
        @currentRecord,
        status
      )
      ret = true
      retcode = SCR.Execute(
        path(".target.bash_output"),
        GetAdmCmd(
          Builtins.sformat(
            "-m node -I%3 -T %1 -p %2 --op=update --name=node.conn[0].startup --value=%4",
            Ops.get(@currentRecord, 1, "").shellescape,
            Ops.get(@currentRecord, 0, "").shellescape,
            Ops.get(@currentRecord, 2, "default").shellescape,
            status.shellescape
          )
        )
      )
      if Ops.greater_than(
        Builtins.size(Ops.get_string(retcode, "stderr", "")),
        0
      )
        return false
      else
        retcode = SCR.Execute(
          path(".target.bash_output"),
          GetAdmCmd(
            Builtins.sformat(
              "-m node -I %3 -T %1 -p %2 --op=update --name=node.startup --value=%4",
              Ops.get(@currentRecord, 1, "").shellescape,
              Ops.get(@currentRecord, 0, "").shellescape,
              Ops.get(@currentRecord, 2, "default").shellescape,
              status.shellescape
            )
          )
        )
      end

      Builtins.y2internal("retcode %1", retcode)
      ret
    end

    def autoLogOn
      ret = true
      log.info "begin of autoLogOn function"
      if !getiBFT.empty?
        result = SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m fw -l"))
        ret = false if result["exit"] != 0
        log.info "Autologin into iBFT : #{result}"
      end
      ret
    end

    def loginIntoTarget(target)
      target = deep_copy(target)
      @currentRecord = [
        Ops.get_string(target, "portal", ""),
        Ops.get_string(target, "target", ""),
        Ops.get_string(target, "iface", "")
      ]
      if Ops.get_string(target, "authmethod", "None") != "None"
        user_in = Ops.get_string(target, "username_in", "")
        pass_in = Ops.get_string(target, "password_in", "")
        if Ops.greater_than(Builtins.size(user_in), 0) &&
            Ops.greater_than(Builtins.size(pass_in), 0)
          setValue("node.session.auth.username_in", user_in)
          setValue("node.session.auth.password_in", pass_in)
        else
          setValue("node.session.auth.username_in", "")
          setValue("node.session.auth.password_in", "")
        end
        user_out = Ops.get_string(target, "username", "")
        pass_out = Ops.get_string(target, "password", "")
        if Ops.greater_than(Builtins.size(user_out), 0) &&
            Ops.greater_than(Builtins.size(pass_out), 0)
          setValue("node.session.auth.username", user_out)
          setValue("node.session.auth.password", pass_out)
          setValue("node.session.auth.authmethod", "CHAP")
        else
          setValue("node.session.auth.username", "")
          setValue("node.session.auth.password", "")
          setValue("node.session.auth.authmethod", "None")
        end
      else
        setValue("node.session.auth.authmethod", "None")
      end

      output = SCR.Execute(
        path(".target.bash_output"),
        GetAdmCmd(
          Builtins.sformat(
            "-m node -I %3 -T %1 -p %2 --login",
            Ops.get_string(target, "target", "").shellescape,
            Ops.get_string(target, "portal", "").shellescape,
            Ops.get_string(target, "iface", "").shellescape
          )
        )
      )
      Builtins.y2internal("output %1", output)

      # Only log the fact that the session is already present (not an error at all)
      # to avoid a popup for AutoYaST install (bsc#981693)
      if output["exit"] == 15
        Builtins.y2milestone("Session already present %1", output["stderr"] || "")
      # Report a warning (not an error) if login failed for other reasons
      # (also related to bsc#981693, warning popups usually are skipped)
      elsif output["exit"] != 0
        Report.Warning(_("Target connection failed.\n") +
                        output["stderr"] || "")
      end

      setStartupStatus("onboot") if !Mode.autoinst
      true
    end

    # FIXME: this method has too much responsibility and it is doing
    # "unexpected" things according to its name. Ideally, it only must return
    # the service status without changing the status of related services and
    # sockets.
    #
    # get status of iscsid
    def getServiceStatus
      ret = true
      if Stage.initial
        ModuleLoading.Load("iscsi_tcp", "", "", "", false, true)
        # start daemon manually (systemd not available in inst-sys)
        start_services_initial
      else
        # find sockets (only in installed system)
        # throw exception if socket not found
        @iscsid_socket = Yast2::Systemd::Socket.find!("iscsid")
        @iscsiuio_socket = Yast2::Systemd::Socket.find!("iscsiuio")

        @iscsi_service_stat = Service.active?("iscsi")
        @iscsid_socket_stat = socketActive?(@iscsid_socket)
        @iscsiuio_socket_stat = socketActive?(@iscsiuio_socket)

        log.info "Status of iscsi.service: #{@iscsi_service_stat}, iscsid.socket: #{@iscsid_socket_stat}, iscsiuio.socket: #{@iscsiuio_socket_stat}"

        # if not running, start iscsi.service, iscsid.socket and iscsiuio.socket
        if !@iscsid_socket_stat
          Service.Stop("iscsid") if Service.active?("iscsid")
          log.error "Cannot start iscsid.socket" if !socketStart(@iscsid_socket)
        end
        if !@iscsiuio_socket_stat
          Service.Stop("iscsiuio") if Service.active?("iscsiuio")
          log.error "Cannot start iscsiuio.socket" if !socketStart(@iscsiuio_socket)
        end
        if !@iscsi_service_stat && !Service.Start("iscsi")
          log.error "Cannot start iscsi.service"
        end
      end
      ret
    end

    # set startup status of iscsid
    def setServiceStatus
      ret = true
      # only makes sense in installed system
      if !Stage.initial
        # if disabled and no connected targets - stop it
        # otherwise keep it running
        if !GetStartService()
          readSessions
          if Builtins.size(@sessions) == 0
            log.info "No active sessions - stopping iscsi service and iscsid/iscsiuio service and socket"
            # stop iscsid.socket and iscsid.service
            socketStop(@iscsid_socket)
            Service.Stop("iscsid")
            # stop iscsiuio.socket and iscsiuio.service
            socketStop(@iscsiuio_socket)
            Service.Stop("iscsiuio")
            # stop iscsi.service
            Service.Stop("iscsi")
          end
        end
      end
      log.info "Status service for iscsid: #{ret}"
      ret
    end

    def autoyastPrepare
      @initiatorname = Ops.get_string(@ay_settings, "initiatorname", "")
      if Ops.greater_than(Builtins.size(@initiatorname), 0)
        file = "/etc/iscsi/initiatorname.iscsi"
        SCR.Write(
          path(".target.string"),
          [file, 384],
          Builtins.sformat("InitiatorName=%1\n", @initiatorname)
        )
      else
        checkInitiatorName
      end
      # start daemon before
      start_services_initial

      nil
    end

    def autoyastWrite
      # do discovery first
      portals = []
      ifaces = []
      ifacepar = ""
      Builtins.foreach(Ops.get_list(@ay_settings, "targets", [])) do |target|
        iface = Ops.get_string(target, "iface", "default")
        if !Builtins.contains(ifaces, iface)
          if Ops.greater_than(Builtins.size(ifacepar), 0)
            ifacepar = Ops.add(ifacepar, " ")
          end
          ifacepar = Ops.add(Ops.add(ifacepar, "-I "), iface)
          ifaces = Builtins.add(ifaces, iface)
        end
      end
      if Ops.greater_than(Builtins.size(Builtins.filter(ifaces) do |s|
                                          s != "default"
                                        end), 0)
        CallConfigScript()
      end
      Builtins.foreach(Ops.get_list(@ay_settings, "targets", [])) do |target|
        if !Builtins.contains(portals, Ops.get_string(target, "portal", ""))
          SCR.Execute(
            path(".target.bash"),
            GetAdmCmd(
              Builtins.sformat(
                "-m discovery %1 -t st -p %2",
                ifacepar.shellescape,
                Ops.get_string(target, "portal", "").shellescape
              )
            )
          )
          portals = Builtins.add(portals, Ops.get_string(target, "portal", ""))
        end
      end
      Builtins.foreach(Ops.get_list(@ay_settings, "targets", [])) do |target|
        Builtins.y2internal("login into target %1", target)
        loginIntoTarget(target)
        @currentRecord = [
          Ops.get_string(target, "portal", ""),
          Ops.get_string(target, "target", ""),
          Ops.get_string(target, "iface", "")
        ]
        setStartupStatus(Ops.get_string(target, "startup", "manual"))
      end
      true
    end

    def Overview
      overview = _("Configuration summary...")
      if Ops.greater_than(Builtins.size(@ay_settings), 0)
        overview = ""
        if Ops.greater_than(
          Builtins.size(Ops.get_string(@ay_settings, "initiatorname", "")),
          0
        )
          overview = Ops.add(
            Ops.add(
              Ops.add(overview, "<p><b>Initiatorname: </b>"),
              Ops.get_string(@ay_settings, "initiatorname", "")
            ),
            "</p>"
          )
        end
        if Ops.greater_than(
          Builtins.size(Ops.get_list(@ay_settings, "targets", [])),
          0
        )
          Builtins.foreach(Ops.get_list(@ay_settings, "targets", [])) do |target|
            overview = Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add(
                      Ops.add(
                        Ops.add(
                          Ops.add(
                            Ops.add(overview, "<p>"),
                            Ops.get_string(target, "portal", "")
                          ),
                          ", "
                        ),
                        Ops.get_string(target, "target", "")
                      ),
                      ", "
                    ),
                    Ops.get_string(target, "iface", "")
                  ),
                  ", "
                ),
                Ops.get_string(target, "startup", "")
              ),
              "</p>"
            )
          end
        end
      end
      overview
    end

    def InitOffloadCard
      ret = "default"
      retcode = SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m node -P 1"))
      ifaces = []
      if Builtins.size(Ops.get_string(retcode, "stderr", "")) == 0
        Builtins.foreach(
          ScanDiscovered(
            Builtins.splitstring(Ops.get_string(retcode, "stdout", ""), "\n")
          )
        ) do |s|
          sl = Builtins.splitstring(s, "  ")
          if Ops.greater_than(Builtins.size(Ops.get(sl, 2, "")), 0) &&
              !Builtins.contains(ifaces, Ops.get(sl, 2, ""))
            ifaces = Builtins.add(ifaces, Ops.get(sl, 2, ""))
          end
        end
      end
      Builtins.y2milestone("InitOffloadCard ifaces:%1", ifaces)
      if Ops.greater_than(Builtins.size(ifaces), 1)
        ret = "all"
      elsif Builtins.contains(@iface_eth, Ops.get(ifaces, 0, ""))
        ret = Ops.get(ifaces, 0, "default")
      end
      Builtins.y2milestone("InitOffloadCard ret:%1", ret)
      ret
    end

    def InitIfaceFile
      @iface_file = {}
      files = Convert.convert(
        SCR.Read(path(".target.dir"), "/etc/iscsi/ifaces"),
        :from => "any",
        :to   => "list <string>"
      )
      Builtins.y2milestone("InitIfaceFile files:%1", files)
      if files == nil || Builtins.size(files) == 0
        cmd = GetAdmCmd("-m iface")
        res = SCR.Execute(path(".target.bash_output"), cmd)
        Builtins.y2milestone("InitIfaceFile cmd:#{cmd}\nres:#{res.inspect}", cmd)
        files = SCR.Read(path(".target.dir"), "/etc/iscsi/ifaces")
        Builtins.y2milestone("InitIfaceFile files:%1", files)
      end
      Builtins.foreach(files) do |file|
        ls = Builtins.splitstring(
          Convert.to_string(
            SCR.Read(
              path(".target.string"),
              Ops.add("/etc/iscsi/ifaces/", file)
            )
          ),
          "\n"
        )
        Builtins.y2milestone("InitIfaceFile file:%1", file)
        Builtins.y2milestone("InitIfaceFile ls:%1", ls)
        ls = Builtins.filter(ls) do |l|
          Builtins.search(l, "iface.iscsi_ifacename") != nil
        end
        Builtins.y2milestone("InitIfaceFile ls:%1", ls)
        if Ops.greater_than(Builtins.size(ls), 0)
          Ops.set(
            @iface_file,
            Ops.get(
              Builtins.splitstring(
                Builtins.deletechars(Ops.get(ls, 0, ""), " "),
                "="
              ),
              1,
              ""
            ),
            file
          )
        end
      end
      Builtins.y2milestone("InitIfaceFile iface_file:%1", @iface_file)

      nil
    end

    def GetOffloadItems
      init = false
      if @offload_valid == nil
        init = true
        InitIfaceFile()
        @offload_valid = {}
        cards = Convert.convert(
          SCR.Read(path(".probe.netcard")),
          :from => "any",
          :to   => "list <map>"
        )

        hw_mods = Builtins.maplist(cards) do |c|
          Builtins.y2milestone("GetOffloadItems card:%1", c)
          tmp = Builtins.maplist(Ops.get_list(c, "drivers", [])) do |m|
            Builtins.flatten(Ops.get_list(m, "modules", []))
          end
          r = {
            "modules" => Builtins.maplist(tmp) { |ml| Ops.get_string(ml, 0, "") },
            "iface"   => Ops.get_string(c, "dev_name", ""),
            "macaddr" => Ops.get_string(
              c,
              ["resource", "hwaddr", 0, "addr"],
              ""
            )
          }
          Builtins.y2milestone("GetOffloadItems cinf:%1", r)
          deep_copy(r)
        end # maplist(cards)

        idx = 0
        Builtins.foreach(@offload) do |l|
          mod = Convert.convert(
            Builtins.sort(Ops.get_list(l, 2, [])),
            :from => "list",
            :to   => "list <string>"
          )
          if Ops.greater_than(Builtins.size(mod), 0)
            Builtins.foreach(hw_mods) do |hw|
              if Ops.greater_than(
                Builtins.size(
                  Builtins::Multiset.intersection(
                    mod,
                    Convert.convert(
                      Builtins.sort(Ops.get_list(hw, "modules", [])),
                      :from => "list",
                      :to   => "list <string>"
                    )
                  )
                ),
                0
              )
                Builtins.y2milestone("GetOffloadItems l:%1", l)
                Builtins.y2milestone("GetOffloadItems valid:%1", hw)
                Ops.set(
                  @offload_valid,
                  idx,
                  Builtins.add(
                    Ops.get(@offload_valid, idx, []),
                    [
                      Ops.get_string(hw, "iface", ""),
                      Ops.get_string(hw, "macaddr", ""),
                      Ops.add(
                        Ops.add(Ops.get_string(hw, "iface", ""), "-"),
                        Ops.get_string(l, [3, 0], "")
                      )
                    ]
                  )
                )
              end
            end
          end
          idx = Ops.add(idx, 1)
        end
        offload_res = {}
        cmd = ""
        Builtins.foreach(@offload_valid) do |i2, eth|
          Ops.set(
            @offload_valid,
            i2,
            Builtins.filter(
              Convert.convert(eth, :from => "list", :to => "list <list>")
            ) do |l|
              cmd = "#{OFFLOAD_SCRIPT} #{Ops.get_string(l, 0, "").shellescape} | grep ..:..:..:.." # grep for lines containing MAC address
              Builtins.y2milestone("GetOffloadItems cmd:%1", cmd)
              out = Convert.to_map(
                SCR.Execute(path(".target.bash_output"), cmd)
              )
              # Example for output if offload is supported on interface:
              # cmd: iscsi_offload eth2
              # out: $["exit":0, "stderr":"", "stdout":"00:00:c9:b1:bc:7f ip \n"]
              result = SCR.Execute(
                path(".target.bash_output"),
                "#{OFFLOAD_SCRIPT} #{Ops.get_string(l, 0, "").shellescape}"
              )
              Builtins.y2milestone(
                "GetOffloadItems iscsi_offload out:%1",
                result
              )
              Ops.set(offload_res, Ops.get_string(l, 0, ""), {})
              Ops.set(
                offload_res,
                [Ops.get_string(l, 0, ""), "exit"],
                Ops.get_integer(out, "exit", 1)
              )
              sl = []
              if Ops.get_integer(out, "exit", 1) == 0
                sl = Builtins.splitstring(
                  Ops.get_string(out, "stdout", ""),
                  " \n"
                )
                Ops.set(
                  offload_res,
                  [Ops.get_string(l, 0, ""), "hwaddr"],
                  Ops.get(sl, 0, "")
                )
                Ops.set(
                  offload_res,
                  [Ops.get_string(l, 0, ""), "ntype"],
                  Ops.get(sl, 1, "")
                )
              end
              Ops.get_integer(out, "exit", 1) == 0 &&
                Ops.greater_than(Builtins.size(Ops.get(sl, 0, "")), 0)
            end
          )
        end
        Builtins.y2milestone("GetOffloadItems offload_res:%1", offload_res)
        Builtins.y2milestone("GetOffloadItems offload_valid:%1", @offload_valid)
        Builtins.foreach(@offload_valid) do |i2, eth|
          Ops.set(
            @offload_valid,
            i2,
            Builtins.maplist(
              Convert.convert(eth, :from => "list", :to => "list <list>")
            ) do |l|
              Ops.set(
                l,
                1,
                Ops.get_string(
                  offload_res,
                  [Ops.get_string(l, 0, ""), "hwaddr"],
                  ""
                )
              )
              deep_copy(l)
            end
          )
        end
        Builtins.y2milestone("GetOffloadItems offload_valid:%1", @offload_valid)
        Builtins.foreach(@offload_valid) do |i2, eth|
          Ops.set(
            @offload_valid,
            i2,
            Builtins.maplist(eth) do |l|
              cmd = "LC_ALL=POSIX /usr/bin/ifconfig " + Ops.get_string(l, 0, "").shellescape # FIXME: ifconfig is deprecated
              Builtins.y2milestone("GetOffloadItems cmd:%1", cmd)
              out = SCR.Execute(path(".target.bash_output"), cmd)
              Builtins.y2milestone("GetOffloadItems out:%1", out)
              # Search for lines containing "init addr", means IPv4 address.
              # Regarding the IPv6 support there are no changes needed here because
              # the IP address is not used farther.
              line = Ops.get(
                Builtins.filter(
                  Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n")
                ) { |ln| Builtins.search(ln, "inet addr:") != nil },
                0,
                ""
              )
              Builtins.y2milestone("GetOffloadItems line:%1", line)
              ipaddr = "unknown"
              if Ops.greater_than(Builtins.size(line), 0)
                line = Builtins.substring(
                  line,
                  Ops.add(Builtins.search(line, "inet addr:"), 10)
                )
                Builtins.y2milestone("GetOffloadItems line:%1", line)
                ipaddr = Builtins.substring(
                  line,
                  0,
                  Builtins.findfirstof(line, " \t")
                )
              end
              l = Builtins.add(l, ipaddr)
              deep_copy(l)
            end
          )
        end
        Builtins.y2milestone("GetOffloadItems offload_valid:%1", @offload_valid)
      end
      entries = {}
      Builtins.foreach(@offload_valid) do |i2, eth|
        Builtins.foreach(
          Convert.convert(eth, :from => "list", :to => "list <list>")
        ) do |l|
          if Ops.greater_than(Builtins.size(Ops.get_string(l, 0, "")), 0)
            s = Ops.get_string(l, 0, "")
            if Ops.greater_than(Builtins.size(Ops.get_string(l, 1, "")), 0)
              s = Ops.add(Ops.add(s, " - "), Ops.get_string(l, 1, ""))
            end
            s = Ops.add(
              Ops.add(s, " - "),
              Ops.get_string(@offload, [i2, 1], "")
            )
            Ops.set(entries, Ops.get_string(l, 2, ""), s)
          end
        end
      end
      Builtins.y2milestone("GetOffloadItems entries:%1", entries)
      @iface_eth = Builtins.sort(Builtins.maplist(entries) { |e, _val| e })
      Builtins.y2milestone("GetOffloadItems eth:%1", @iface_eth)
      if init
        @offload_card = InitOffloadCard()
        Builtins.y2milestone("GetOffloadItems offload_card:%1", @offload_card)
      end
      ret = [
        Item(
          Id(Ops.get_string(@offload, [0, 0], "")),
          Ops.get_string(@offload, [0, 1], ""),
          @offload_card == Ops.get_string(@offload, [0, 0], "")
        )
      ]
      if Ops.greater_than(Builtins.size(@offload_valid), 0)
        ret = Builtins.add(
          ret,
          Item(
            Id(Ops.get_string(@offload, [1, 0], "")),
            Ops.get_string(@offload, [1, 1], ""),
            @offload_card == Ops.get_string(@offload, [1, 0], "")
          )
        )
      end
      ret = Convert.convert(
        Builtins.merge(ret, Builtins.maplist(@iface_eth) do |e|
          Item(Id(e), Ops.get(entries, e, ""), @offload_card == e)
        end),
        :from => "list",
        :to   => "list <term>"
      )
      Builtins.y2milestone("GetOffloadItems ret:%1", ret)
      deep_copy(ret)
    end

    def GetOffloadModules
      GetOffloadItems() if @offload_valid == nil
      modules = []
      Builtins.foreach(@offload_valid) do |i, _l|
        modules = Convert.convert(
          Builtins.union(modules, Ops.get_list(@offload, [i, 3], [])),
          :from => "list",
          :to   => "list <string>"
        )
      end
      Builtins.y2milestone("GetOffloadModules %1", modules)
      deep_copy(modules)
    end

    def LoadOffloadModules
      mods = GetOffloadModules()
      Builtins.foreach(mods) do |s|
        Builtins.y2milestone("Loading module %1", s)
        ModuleLoading.Load(s, "", "", "", false, true)
      end
      deep_copy(mods)
    end

    def GetDiscIfaces
      ret = []
      if GetOffloadCard() == "all"
        tl = Builtins.maplist(GetOffloadItems()) do |t|
          Ops.get_string(Builtins.argsof(t), [0, 0], "")
        end
        Builtins.y2milestone("GetDiscIfaces:%1", tl)
        ret = Builtins.filter(tl) { |s| s != "all" }
      else
        ret = [GetOffloadCard()]
      end
      Builtins.y2milestone("GetDiscIfaces:%1", ret)
      deep_copy(ret)
    end

    def CallConfigScript
      sl = Builtins.filter(GetDiscIfaces()) { |s| s != "default" }
      Builtins.y2milestone("CallConfigScript list:%1", sl)
      Builtins.foreach(sl) do |s|
        hw = []
        hw = Ops.get(Builtins.maplist(Builtins.filter(@offload_valid) do |_i, eth|
          Builtins.contains(
            Builtins.flatten(
              Convert.convert(eth, :from => "list", :to => "list <list>")
            ),
            s
          )
        end) { |_i, e| e }, 0, [])
        Builtins.y2milestone("CallConfigScript hw:%1", hw)
        hw = Builtins.find(
          Convert.convert(hw, :from => "list", :to => "list <list>")
        ) { |l| Ops.get_string(l, 2, "") == s }
        Builtins.y2milestone("CallConfigScript hw:%1", hw)
        if hw != nil
          cmd = "#{OFFLOAD_SCRIPT} #{Ops.get_string(hw, 0, "").shellescape}"
          Builtins.y2milestone("CallConfigScript cmd:%1", cmd)
          output = SCR.Execute(path(".target.bash_output"), cmd)
          Builtins.y2milestone("CallConfigScript %1", output)
        end
      end

      nil
    end

    def GetDiscoveryCmd(ip, port, use_fw: false, only_new: false)
      Builtins.y2milestone("GetDiscoveryCmd ip:%1 port:%2 fw:%3 only new:%4",
        ip, port, use_fw, only_new)
      command = "-m discovery -P 1"
      isns_info = useISNS
      if isns_info["use"]
        command << " -t isns -p #{ip}:#{port}"
      else
        ifs = GetDiscIfaces()
        Builtins.y2milestone("ifs=%1", ifs)
        ifs = Builtins.maplist(ifs) { |s| Ops.add("-I ", s) }
        Builtins.y2milestone("ifs=%1", ifs)
        tgt = "st"
        tgt = "fw" if use_fw
        command << " -t #{tgt} #{ifs.join(" ")} -p #{ip}:#{port}"
      end
      command << " -o new" if only_new

      command = GetAdmCmd(command)
      Builtins.y2milestone("GetDiscoveryCmd %1", command)
      command
    end

    publish :variable => :sessions, :type => "list <string>"
    publish :variable => :discovered, :type => "list <string>"
    publish :variable => :targets, :type => "list <string>"
    publish :variable => :currentRecord, :type => "list <string>"
    publish :variable => :initiatorname, :type => "string"
    publish :variable => :ay_settings, :type => "map"
    publish :function => :GetOffloadCard, :type => "string ()"
    publish :function => :SetOffloadCard, :type => "void (string)"
    publish :function => :GetAdmCmd, :type => "string (string)"
    publish :function => :hidePassword, :type => "map <string, any> (map <string, any>)"
    publish :function => :getiBFT, :type => "map <string, any> ()"
    publish :function => :GetStartService, :type => "boolean ()"
    publish :function => :SetStartService, :type => "void (boolean)"
    publish :function => :getConfig, :type => "list <map <string, any>> ()"
    publish :function => :setConfig, :type => "void (list)"
    publish :function => :useISNS, :type => "map <string, any> ()"
    publish :function => :oldConfig, :type => "void ()"
    publish :function => :getNode, :type => "map <string, any> ()"
    publish :function => :saveConfig, :type => "void (string, string, string, string)"
    publish :function => :ScanDiscovered, :type => "list <string> (list <string>)"
    publish :function => :getDiscovered, :type => "list <string> ()"
    publish :function => :start_services_initial, :type => "void ()"
    publish :function => :readSessions, :type => "boolean ()"
    publish :function => :writeInitiatorName, :type => "boolean (string)"
    publish :function => :checkInitiatorName, :type => "boolean ()"
    publish :function => :deleteRecord, :type => "boolean ()"
    publish :function => :getStartupStatus, :type => "string ()"
    publish :function => :setValue, :type => "boolean (string, string)"
    publish :function => :connected, :type => "boolean (boolean)"
    publish :function => :setStartupStatus, :type => "boolean (string)"
    publish :function => :autoLogOn, :type => "boolean ()"
    publish :function => :loginIntoTarget, :type => "boolean (map)"
    publish :function => :getServiceStatus, :type => "boolean ()"
    publish :function => :setServiceStatus, :type => "boolean ()"
    publish :function => :autoyastPrepare, :type => "boolean ()"
    publish :function => :autoyastWrite, :type => "boolean ()"
    publish :function => :Overview, :type => "string ()"
    publish :function => :GetOffloadItems, :type => "list <term> ()"
    publish :function => :GetOffloadModules, :type => "list <string> ()"
    publish :function => :LoadOffloadModules, :type => "list <string> ()"
    publish :function => :GetDiscoveryCmd, :type => "string (string, string, map)"
    publish :function => :getCurrentNodeValues, :type => "map <string, any> ()"
    publish :function => :iBFT?, :type => "boolean (map <string, any>)"
  end

  IscsiClientLib = IscsiClientLibClass.new
  IscsiClientLib.main
end
