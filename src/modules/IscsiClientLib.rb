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
require 'ipaddr'

module Yast
  class IscsiClientLibClass < Module

    include Yast::Logger

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
      Yast.import "SystemdSocket"

      @sessions = []
      @discovered = []
      @targets = []
      @currentRecord = []
      @iface_file = {}
      @iface_eth = []

      # status of iscsi.service
      @serviceStatus = false
      # status of iscsid.socket
      @socketStatus = false
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

      @offboard_script = "iscsi_offload"

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
    end

    def iscsidSocketActive?
      if @iscsid_socket
        @iscsid_socket.active?
      else
        log.error("iscsid.socket not found")
        false
      end
    end

    def iscsidSocketStart
      if @iscsid_socket
        @iscsid_socket.start
      else
        log.error("iscsid.socket not found")
        false
      end
    end

    def iscsidSocketStop
      if @iscsid_socket
        @iscsid_socket.stop
     else
        log.error("iscsid.socket not found")
        false
      end
    end

    def iscsidSocketEnabled?
      if @iscsid_socket
        @iscsid_socket.enabled?
      else
        log.error("iscsid.socket not found")
        false
      end
    end

    def iscsidSocketDisabled?
      if @iscsid_socket
        @iscsid_socket.disabled?
      else
        log.error("iscsid.socket not found")
        false
      end
    end

    def iscsidSocketEnable
      if @iscsid_socket
        @iscsid_socket.enable
      else
        log.error("iscsid.socket not found")
        false
      end
    end

    def iscsidSocketDisable
      if @iscsid_socket
        @iscsid_socket.disable
      else
        log.error("iscsid.socket not found")
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
    def GetAdmCmd(params, do_log=true)
      ret = "LC_ALL=POSIX iscsiadm"
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


    # get iBFT (available only on some special hardware)
    def getiBFT
      if @ibft == nil
        if !Arch.i386 && !Arch.x86_64
          Builtins.y2milestone(
            "Because architecture %1 is is different from x86, not using iBFT",
            Arch.arch_short
          )
          return {}
        end
        @ibft = {}
        Builtins.y2milestone(
          "check and modprobe iscsi_ibft : %1",
          SCR.Execute(
            path(".target.bash_output"),
            "lsmod |grep -q iscsi_ibft || modprobe iscsi_ibft"
          )
        )
        from_bios = Ops.get_string(
          Convert.convert(
            SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m fw")),
            :from => "any",
            :to   => "map <string, any>"
          ),
          "stdout",
          ""
        )
        Builtins.foreach(Builtins.splitstring(from_bios, "\n")) do |row|
          key_val = Builtins.splitstring(row, "=")
          #   if (size(key_val[0]:"")>0) ibft[key_val[0]:""] = key_val[1]:"";
          kv = String.CutBlanks(Ops.get(key_val, 0, ""))
          if Ops.greater_than(Builtins.size(kv), 0)
            Ops.set(@ibft, kv, String.CutBlanks(Ops.get(key_val, 1, "")))
          end
        end
      end
      Builtins.y2milestone("iBFT %1", hidePassword(@ibft))
      deep_copy(@ibft)
    end


    # get accessor for service status
    def GetStartService
      status_d = iscsidSocketEnabled?
      status = Service.Enabled("iscsi")
      Builtins.y2milestone("Start at boot enabled for iscsid.socket: %1, iscsi: %2", status_d, status)
      return status_d && status
    end

    # set accessor for service status
    def SetStartService(status)
      Builtins.y2milestone("Set start at boot for iscsid.socket and iscsi.service to %1",
                            status)
      if status == true
        Service.Enable("iscsi")
        iscsidSocketEnable
      else
        Service.Disable("iscsi")
        iscsidSocketDisable
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
      use = false
      Builtins.foreach(getConfig) do |row|
        if Ops.get_string(row, "name", "") == "isns.address" ||
            Ops.get_string(row, "name", "") == "isns.port"
          use = true
        end
      end
      use
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
          Ops.get(@currentRecord, 1, ""),
          Ops.get(@currentRecord, 0, ""),
          Ops.get(@currentRecord, 2, "default")
        )
      )
      cmd = Convert.convert(
        SCR.Execute(path(".target.bash_output"), cmdline),
        :from => "any",
        :to   => "map <string, any>"
      )
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

      if Ops.greater_than(Builtins.size(user_in), 0) &&
          Ops.greater_than(Builtins.size(pass_in), 0)
        tmp_val = setOrAdd(tmp_val, "node.session.auth.username", user_in)
        tmp_val = setOrAdd(tmp_val, "node.session.auth.password", pass_in)
      else
        tmp_val = delete(tmp_val, "node.session.auth.username")
        tmp_val = delete(tmp_val, "node.session.auth.password")
      end

      if Ops.greater_than(Builtins.size(user_out), 0) &&
          Ops.greater_than(Builtins.size(pass_out), 0)
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
        tmp_val = delete(tmp_val, "discovery.sendtargets.auth.authmethod")
        tmp_val = delete(tmp_val, "discovery.sendtargets.auth.username")
        tmp_val = delete(tmp_val, "discovery.sendtargets.auth.password")
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
      retcode = Convert.convert(
        SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m node -P 1")),
        :from => "any",
        :to   => "map <string, any>"
      )
      if Builtins.size(Ops.get_string(retcode, "stderr", "")) == 0
        @discovered = ScanDiscovered(
          Builtins.splitstring(Ops.get_string(retcode, "stdout", ""), "\n")
        )
      end
      deep_copy(@discovered)
    end


    def startIScsid
      SCR.Execute(path(".target.bash"), "pgrep iscsid || iscsid")
      Builtins.foreach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) do |i|
        Builtins.sleep(1 * 1000)
        cmd = Convert.convert(
          SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m session")),
          :from => "any",
          :to   => "map <string, any>"
        )
        Builtins.y2internal(
          "iteration %1, retcode %2",
          i,
          Ops.get_integer(cmd, "exit", -1)
        )
        if Ops.get_integer(cmd, "exit", -1) == 0
          Builtins.y2internal("Good response from daemon, exit.")
          raise Break
        end
      end

      nil
    end

    # get all connected targets
    def readSessions
      Builtins.y2milestone("reading current settings")
      retcode = Convert.convert(
        SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m session -P 1")),
        :from => "any",
        :to   => "map <string, any>"
      )
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
          Builtins.sformat("mv %1 /etc/iscsi/initiatorname.yastbackup", file)
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
      Service.Restart("iscsid")
      ret
    end

    def getReverseDomainName
      host_fq = Hostname.SplitFQ(
        Ops.get_string(
          Convert.convert(
            SCR.Execute(path(".target.bash_output"), "hostname -f|tr -d '\n'"),
            :from => "any",
            :to   => "map <string, any>"
          ),
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
      name_from_bios = Ops.get_string(getiBFT, "iface.initiatorname", "")
      # if (size((map<string, any>)SCR::Read (.target.lstat, file)) == 0 || ((map<string, any>)SCR::Read (.target.lstat, file))["size"]:0==0){
      @initiatorname = Ops.get_string(
        Convert.convert(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "grep -v '^#' %1 | grep InitiatorName | cut -d'=' -f2 | tr -d '\n'",
              file
            )
          ),
          :from => "any",
          :to   => "map <string, any>"
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
          domain = Ops.get_string(
            Convert.convert(
              SCR.Execute(path(".target.bash_output"), ""),
              :from => "any",
              :to   => "map <string, any>"
            ),
            "stdout",
            "com.example"
          )
          output = Convert.convert(
            SCR.Execute(
              path(".target.bash_output"),
              Builtins.sformat(
                "/sbin/iscsi-iname -p iqn.%1.%2:01 | tr -d '\n'",
                "`date +%Y-%m`",
                getReverseDomainName
              ),
              {}
            ),
            :from => "any",
            :to   => "map <string, any>"
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
              "InitiatorName from iBFT and from <tt>/etc/iscsi/initiatorname.iscsi</tt>\n" +
                "differ. The old initiator name will be replaced by the value of iBFT and a \n" +
                "backup created. If you want to use a different initiator name, change it \n" +
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

      retcode = Convert.convert(
        SCR.Execute(
          path(".target.bash_output"),
          GetAdmCmd(
            Builtins.sformat(
              "-m node -I %3 -T %1 -p %2 --logout",
              Ops.get(@currentRecord, 1, ""),
              Ops.get(@currentRecord, 0, ""),
              Ops.get(@currentRecord, 2, "default")
            )
          )
        ),
        :from => "any",
        :to   => "map <string, any>"
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

    # get (manual/onboot) status of target connecting
    def getStartupStatus
      status = ""
      Builtins.y2milestone("Getting status of record %1", @currentRecord)
      retcode = Convert.convert(
        SCR.Execute(
          path(".target.bash_output"),
          GetAdmCmd(
            Builtins.sformat(
              "-m node -I %3 -T %1 -p %2",
              Ops.get(@currentRecord, 1, ""),
              Ops.get(@currentRecord, 0, ""),
              Ops.get(@currentRecord, 2, "default")
            )
          )
        ),
        :from => "any",
        :to   => "map <string, any>"
      )
      if Ops.greater_than(
          Builtins.size(Ops.get_string(retcode, "stderr", "")),
          0
        )
        return ""
      end
      Builtins.foreach(
        Builtins.splitstring(Ops.get_string(retcode, "stdout", ""), "\n")
      ) do |row|
        if Builtins.issubstring(row, "node.conn[0].startup")
          status = Ops.get(Builtins.splitstring(row, " "), 2, "")
          raise Break
        end
      end
      Builtins.y2milestone(
        "Startup status for %1 is %2",
        @currentRecord,
        status
      )
      status
    end

    # update authentication value
    def setValue(name, value)
      rec = @currentRecord
      Builtins.y2milestone("set %1  for record %2", name, rec)

      log = !name.include?("password");
      cmd = "-m node -I #{rec[2]||"default"} -T #{rec[1]||""} -p #{rec[0]||""} --name=#{name}"

      command = GetAdmCmd("#{cmd} --value=#{value}", log)
      if !log
        value = "*****" if !value.empty?
        Builtins.y2milestone("AdmCmd:LC_ALL=POSIX iscsiadm #{cmd} --value=#{value}")
      end

      ret = true
      retcode = Convert.convert(
        SCR.Execute(path(".target.bash_output"), command),
        :from => "any",
        :to   => "map <string, any>"
      )
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
      if !session_ip || !current_ip
        return false
      end
      if session_ip.empty? || current_ip.empty?
        return false
      end

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
      Builtins.y2error("Invalid IP address, error: %1", "#{e}")
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
                               0, "" )
          current_ip = Ops.get(
                               Builtins.splitstring(Ops.get(@currentRecord, 0, ""), ","),
                               0, "" )
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
      retcode = Convert.convert(
        SCR.Execute(
          path(".target.bash_output"),
          GetAdmCmd(
            Builtins.sformat(
              "-m node -I%3 -T %1 -p %2 --op=update --name=node.conn[0].startup --value=%4",
              Ops.get(@currentRecord, 1, ""),
              Ops.get(@currentRecord, 0, ""),
              Ops.get(@currentRecord, 2, "default"),
              status
            )
          )
        ),
        :from => "any",
        :to   => "map <string, any>"
      )
      if Ops.greater_than(
          Builtins.size(Ops.get_string(retcode, "stderr", "")),
          0
        )
        return false
      else
        retcode = Convert.convert(
          SCR.Execute(
            path(".target.bash_output"),
            GetAdmCmd(
              Builtins.sformat(
                "-m node -I %3 -T %1 -p %2 --op=update --name=node.startup --value=%4",
                Ops.get(@currentRecord, 1, ""),
                Ops.get(@currentRecord, 0, ""),
                Ops.get(@currentRecord, 2, "default"),
                status
              )
            )
          ),
          :from => "any",
          :to   => "map <string, any>"
        )
      end

      Builtins.y2internal("retcode %1", retcode)
      ret
    end

    def autoLogOn
      Builtins.y2milestone("begin of autoLogOn function")
      if Ops.greater_than(Builtins.size(getiBFT), 0)
        Builtins.y2milestone(
          "Autologin into iBFT : %1",
          SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m fw -l"))
        )
      end
      true
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

      output = Convert.convert(
        SCR.Execute(
          path(".target.bash_output"),
          GetAdmCmd(
            Builtins.sformat(
              "-m node -I %3 -T %1 -p %2 --login",
              Ops.get_string(target, "target", ""),
              Ops.get_string(target, "portal", ""),
              Ops.get_string(target, "iface", "")
            )
          )
        ),
        :from => "any",
        :to   => "map <string, any>"
      )
      Builtins.y2internal("output %1", output)
      # if (output["exit"]:-1==0){
      # set startup status to auto by default (bnc#400610)
      setStartupStatus("onboot") if !Mode.autoinst
      true 
      # } else {
      # 	y2error("Error while Log-on into target : %1", output);
      # 	return false;
      # 	}
    end


    # get status of iscsid
    def getServiceStatus
      ret = true
      if Stage.initial
        ModuleLoading.Load("iscsi_tcp", "", "", "", false, true)
        # start daemon manually (systemd not available in inst-sys)
        startIScsid
      else
        # find socket (only in installed system)
        # throw exception if socket not found
        @iscsid_socket = SystemdSocket.find!("iscsid")

        @serviceStatus = true if Service.Status("iscsi") == 0
        @socketStatus = true if iscsidSocketActive?
        Builtins.y2milestone("Status of iscsi.service = %1 iscsid.socket = %2",
                             @serviceStatus, @socketStatus)
        # if not running, start iscsi.service and iscsid.socket
        if !@socketStatus
          Service.Stop("iscsid") if Service.Status("iscsid") == 0 
          Builtins.y2error("Cannot start iscsid.socket") if !iscsidSocketStart
        end
        if !@serviceStatus && !Service.Start("iscsi")
          Builtins.y2error("Cannot start iscsi.service")
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
            Builtins.y2milestone("No active sessions - stopping iscsi
                                  service and iscsid service/socket")
            # stop iscsid.socket and iscsid.service 
            iscsidSocketStop
            Service.Stop("iscsid")
            Service.Stop("iscsi")
          end
        end
      end
      Builtins.y2milestone("Status service for iscsid: %1", ret)
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
      startIScsid

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
                ifacepar,
                Ops.get_string(target, "portal", "")
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
      retcode = Convert.convert(
        SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m node -P 1")),
        :from => "any",
        :to   => "map <string, any>"
      )
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
        Builtins.y2milestone("InitIfaceFile cmd:%1", cmd)
        Builtins.y2milestone(
          "InitIfaceFile ret:%1",
          SCR.Execute(path(".target.bash_output"), cmd)
        )
        files = Convert.convert(
          SCR.Read(path(".target.dir"), "/etc/iscsi/ifaces"),
          :from => "any",
          :to   => "list <string>"
        )
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
      i = 0
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
        end
        idx = 0
        Builtins.foreach(@offload) do |l|
          valid = false
          mod = Convert.convert(
            Builtins.sort(Ops.get_list(l, 2, [])),
            :from => "list",
            :to   => "list <string>"
          )
          if Ops.greater_than(Builtins.size(mod), 0)
            i = 0
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
              cmd = Ops.add(
                Ops.add(
                  Ops.add(@offboard_script, " "),
                  Ops.get_string(l, 0, "")
                ),
                " | grep ..:..:..:.."     # grep for lines containing MAC address
              )
              Builtins.y2milestone("GetOffloadItems cmd:%1", cmd)
              out = Convert.to_map(
                SCR.Execute(path(".target.bash_output"), cmd)
              )
              # Example for output if offload is supported on interface:
              # cmd: iscsi_offload eth2
              # out: $["exit":0, "stderr":"", "stdout":"00:00:c9:b1:bc:7f ip \n"]
              Builtins.y2milestone(
                "GetOffloadItems iscsi_offload out:%1",
                SCR.Execute(
                  path(".target.bash_output"),
                  Ops.add(
                    Ops.add(@offboard_script, " "),
                    Ops.get_string(l, 0, "")
                  )
                )
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
            Builtins.maplist(
              Convert.convert(eth, :from => "list", :to => "list <list>")
            ) do |l|
              cmd = Ops.add("LC_ALL=POSIX ifconfig ", Ops.get_string(l, 0, ""))
              Builtins.y2milestone("GetOffloadItems cmd:%1", cmd)
              out = Convert.to_map(
                SCR.Execute(path(".target.bash_output"), cmd)
              )
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
      @iface_eth = Builtins.sort(Builtins.maplist(entries) { |e, val| e })
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
      it = nil
      it = GetOffloadItems() if @offload_valid == nil
      modules = []
      Builtins.foreach(@offload_valid) do |i, l|
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
        hw = Ops.get(Builtins.maplist(Builtins.filter(@offload_valid) do |i, eth|
          Builtins.contains(
            Builtins.flatten(
              Convert.convert(eth, :from => "list", :to => "list <list>")
            ),
            s
          )
        end) { |i, e| e }, 0, [])
        Builtins.y2milestone("CallConfigScript hw:%1", hw)
        hw = Builtins.find(
          Convert.convert(hw, :from => "list", :to => "list <list>")
        ) { |l| Ops.get_string(l, 2, "") == s }
        Builtins.y2milestone("CallConfigScript hw:%1", hw)
        if hw != nil
          cmd = Ops.add(
            Ops.add(@offboard_script, " "),
            Ops.get_string(hw, 0, "")
          )
          Builtins.y2milestone("CallConfigScript cmd:%1", cmd)
          output = Convert.to_map(SCR.Execute(path(".target.bash_output"), cmd))
          Builtins.y2milestone("CallConfigScript %1", output)
        end
      end

      nil
    end

    def GetDiscoveryCmd(ip, port, fw)
      Builtins.y2milestone("GetDiscoveryCmd ip:%1 port:%2 fw:%3", ip, port, fw)
      command = "-m discovery -P 1"
      if useISNS
        command = Ops.add(command, " -t isns")
      else
        ifs = GetDiscIfaces()
        Builtins.y2milestone("ifs=%1", ifs)
        ifs = Builtins.maplist(ifs) { |s| Ops.add("-I ", s) }
        Builtins.y2milestone("ifs=%1", ifs)
        tgt = "st"
        tgt = "fw" if fw
        command = Ops.add(
          command,
          Builtins.sformat(
            " -t %4 %3 -p %1:%2",
            ip,
            port,
            Builtins.mergestring(ifs, " "),
            tgt
          )
        )
      end
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
    publish :function => :useISNS, :type => "boolean ()"
    publish :function => :oldConfig, :type => "void ()"
    publish :function => :getNode, :type => "map <string, any> ()"
    publish :function => :saveConfig, :type => "void (string, string, string, string)"
    publish :function => :ScanDiscovered, :type => "list <string> (list <string>)"
    publish :function => :getDiscovered, :type => "list <string> ()"
    publish :function => :startIScsid, :type => "void ()"
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
    publish :function => :GetDiscoveryCmd, :type => "string (string, string, boolean)"
  end

  IscsiClientLib = IscsiClientLibClass.new
  IscsiClientLib.main
end
