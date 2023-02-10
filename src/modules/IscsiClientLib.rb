# encoding: utf-8

# |***************************************************************************
# |
# | Copyright (c) [2012-2023] SUSE LLC
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
# | along with this program; if not, contact SUSE LLC
# |
# | To contact Novell about this file by physical or electronic mail,
# | you may find current contact information at www.suse.com
# |
# |***************************************************************************
require "yast"
require "yast2/systemd/socket"
require "ipaddr"
require "y2iscsi_client/config"
require "y2iscsi_client/timeout_process"
require "y2iscsi_client/authentication"

require "shellwords"

module Yast
  class IscsiClientLibClass < Module
    include Yast::Logger

    Yast.import "Arch"

    # Script to configure iSCSI offload engines for use with open-iscsi
    #
    # Relying on our secure $PATH (set in y2start), not making assumptions
    # if the binary is in /sbin or in /usr/sbin (usr-merge in openSUSE!)
    # (bsc#1196086, bsc#1196086)
    OFFLOAD_SCRIPT = "iscsi_offload".freeze

    # Driver modules that depend on the iscsiuio service/socket
    #
    # @see #iscsiuio_relevant?
    #
    # The modules match with the ones specified as the fourth element of the relevant entries
    # at @offload.
    #
    # @return [Array<String>]
    ISCSIUIO_MODULES = ["bnx2i", "qedi"].freeze
    private_constant :ISCSIUIO_MODULES

    # Documentation for attributes that are initialized at #main

    # @!attribute sessions
    #   All connected nodes found via #readSessions
    #
    #   In Open-iscsi, the term "node" refers to a portal on a target
    #
    #   Each session is represented by a string of the form "portal target iface"
    #
    #   @return [Array<String>] ex. ["192.168.122.47:3260 iqn.2022-12.com.example:3dafafa2 default"]

    # @!attribute discovered
    # Entries in the local nodes database, populated via #getDiscovered
    #
    # Each node is represented by a string of the same form than in {#sessions}
    #
    # @return [Array<String>]

    # @!attribute targets
    #   List of nodes found by the latest discovery
    #
    #   Each target is represented by a string of the same form than in {#sessions}
    #
    #   @return [Array<String>]

    # @!attribute currentRecord
    #   Node used as a target for most operations offered by the IscsiClientLib module
    #
    #   Consists on an array in which the first element is the portal, the second is the target
    #   and the third is the iSCSI interface (ie. similar to the strings in {#sessions},
    #   {#discovered} or {#targets} but using an array instead of a space-separated string).
    #
    #   @return [Array<String>]

    # Constructor
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

      # For information about these variables, see the YARDoc documentation above
      @sessions = []
      @discovered = []
      @targets = []
      @currentRecord = []
      @iface_file = {}
      @iface_eth = []

      # Content of the main configuration file (/etc/iscsi/iscsid.conf)
      # Use {#getConfig} and {#setConfig} to deal with its content in a convenient way.
      @config = Y2IscsiClient::Config.new

      # iBFT (iSCSI Boot Firmware Table)
      @ibft = nil
      # InitiatorName file (/etc/iscsi/initiatorname.iscsi)
      @initiatorname = ""
      # map used for autoYaST
      @ay_settings = nil
      # interface type for hardware offloading
      @offload_card = "default"

      # Types of offload cards
      # [<id>, <label>, <matching_modules>, <load_modules>]
      #
      # matching_modules => used to identify if a given netcard in the system belongs to this type.
      # That's the case if any of the modules used by the card (according to hwinfo) matches with
      # any module from this list
      # load_modules => modules to load if the given type of card is used
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
        ["be2net", "be2net/be2iscsi", ["be2net", "be2iscsi"], ["be2iscsi"]],
        ["qed", "qede/qedi", ["qede", "qedi"], ["qedi"]]
      ]

      # Network cards in the system that can be used as offload card, grouped by its type.
      # This is a hash like this:
      # { <idx> => [ <card1>, <card2>, ...], ...}
      #
      # idx => index of the type of card at @offload
      # cardX => Array with 4 elements [ <iface>, <mac>, <iscsi>, <ipaddr> ]
      #   iface => device name of the interface (eg. eth0)
      #   mac => hardware address
      #   iscsi => name of the open-iscsi interface definition in the style <iface>-<module>
      #   ipaddr => IPv4 address
      #
      # Eg.
      # {
      #   2 => [ ["eth4", "00:11:22:33:44:55:66", "eth4-bnx2i", "191.212.2.2"] ],
      #   6 => [
      #          ["eth0", "00:...:33", "eth0-be2iscsi", "12.16.0.1"],
      #          ["eth1", "00:...:11", "eth1-be2iscsi", "19.2.20.1"]
      #        ]
      # }
      #
      @offload_valid = nil

      # Very likely, these two instance variables should NOT be directly accessed everywhere in
      # this class. It would be more sane to rely on accessors with memoization like this:
      #
      #   def iscsid_socket
      #     @iscsid_socket ||= Yast2::Systemd::Socket.find!("iscsid")
      #   end
      #
      # Currently there are several methods that seem to rely on these variables been initialized,
      # which only happens during #getServiceStatus.
      #
      # But having sane accessors and breaking those dependencies between method calls would
      # introduce changes in behavior, so it must be done carefully. Maybe some functionality relies
      # on the current logic, even if it looks broken by design.
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
      ret = "LC_ALL=POSIX iscsiadm #{params}"
      Builtins.y2milestone("GetAdmCmd: #{ret}") if do_log
      ret
    end

    def hidePassword(orig)
      hidden = deep_copy(orig)
      hidden.each do |key, _value|
        next unless key.include?("PASS")
        hidden[key] = "*****"
      end
      hidden
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
        retval[key] = val.to_s.strip if !key.empty? && !key.match?(/^#/)
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
          "lsmod | grep -q iscsi_ibft || modprobe iscsi_ibft")
        log.info "check and modprobe iscsi_ibft: #{ret}"

        @ibft = nodeInfoToMap(getFirmwareInfo)
      end

      log.info "iBFT: #{hidePassword(@ibft)}"
      @ibft
    end

    # get accessor for service status
    #
    # NOTE: this is reliable only if {#getServiceStatus} has been called before (since that's
    # the only way to initialize @iscsid_socket and @iscsiuio_socket). Not sure if that method
    # interdependency is intentional (looks dangerous).
    def GetStartService
      status_d = socketEnabled?(@iscsid_socket)
      status_uio = socketEnabled?(@iscsiuio_socket)
      status = Service.Enabled("iscsi")
      log.info "Start at boot enabled for iscsid.socket: #{status_d}, iscsi: #{status}, iscsiuio.socket: #{status_uio}"
      log.info "Is iscsiuio relevant? #{iscsiuio_relevant?}"
      return status_d && status && !(iscsiuio_relevant? && !status_uio)
    end

    # set accessor for service status
    #
    # NOTE: this can handle the iscsid and iscsiuio sockets only if {#getServiceStatus} has been
    # called before. Not sure if that method interdependency is intentional (looks dangerous).
    def SetStartService(status)
      msg =
        if iscsiuio_relevant?
          "Set start at boot for iscsid.socket, iscsiuio.socket and iscsi.service to #{status}"
        else
          "Set start at boot for iscsid.socket and iscsi.service to #{status}"
        end
      log.info msg

      if status == true
        Service.Enable("iscsi")
        socketEnable(@iscsid_socket)
        socketEnable(@iscsiuio_socket) if iscsiuio_relevant?
      else
        Service.Disable("iscsi")
        socketDisable(@iscsid_socket)
        socketDisable(@iscsiuio_socket) if iscsiuio_relevant?
      end

      nil
    end

    # Current configuration
    #
    # returns an array with all the entries of the configuration, each entry
    # represented by hash that follows the structure of the yast init-agent.
    #
    # @return [Array<Hash>]
    def getConfig
      # use cache if available
      @config.read if @config.empty?
      @config.entries
    end

    # Updates the in-memory representation of the configuration
    #
    # @see #getConfig
    #
    # @param new_config [Array<Hash>]
    def setConfig(new_config)
      @config.entries = deep_copy(new_config)
      nil
    end

    # do we use iSNS for targets?
    def useISNS
      isns_info = { "use" => false, "address" => "", "port" => "3205" }
      # validateISNS checks for not empty address and port,
      # storeISNS adds values to config
      getConfig.each do |row|
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
      @config.save
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

    # @see #save_auth_config
    #
    # Offered for backwards compatibility
    def saveConfig(user_in, pass_in, user_out, pass_out)
      values = {
        "username_in" => user_in, "password_in" => pass_in,
        "username" => user_out, "password" => pass_out
      }
      auth = Y2IscsiClient::Authentication.new_from_legacy(values)
      save_auth_config(auth)
    end

    # Temporary change config for discovery authentication
    #
    # Writes the authentication settings to the iscsid.conf file without altering the memory
    # representation of that file that is stored at @config. That makes possible to undo the
    # changes in the file later by calling {#oldConfig}.
    #
    # @param auth [Authentication] authentication settings to use for discovery operations
    def save_auth_config(auth)
      Builtins.y2milestone("Save config")
      tmp_conf = deep_copy(@config)

      tmp_conf.set_discovery_auth(auth)
      tmp_conf.save
      nil
    end

    # Executes an iSCSI discovery using Send Targets and stores the result (the found
    # nodes) at {#targets}.
    #
    # The discovery operation will update the local send_targets database, so a subsequent
    # call to {#getDiscovered} would report the discovered nodes in addition to the previously
    # known ones.
    #
    # @return [Boolean] whether the discovery operation succeeded and {#targets} contains a
    #   valid result
    def discover(host, port, auth, only_new: false, silent: false)
      # temporarily write authentication data to /etc/iscsi/iscsi.conf
      save_auth_config(auth)

      # The discovery command can take care of loading the needed kernel modules.
      # But that doesn't work when YaST is running (and thus executing the
      # discovery command) in a container. So this loads the modules in advance
      # in a way that works in containers.
      load_modules

      command = GetDiscoveryCmd(host, port, only_new: only_new, use_fw: false)
      success, trg_list = Y2IscsiClient::TimeoutProcess.run(command, silent: silent)

      if trg_list.empty?
        command = GetDiscoveryCmd(host, port, only_new: only_new, use_fw: true)
        success, trg_list = Y2IscsiClient::TimeoutProcess.run(command, silent: silent)
      end

      self.targets = ScanDiscovered(trg_list)
      # Restore into iscsi.conf the configuration previously saved in memory
      oldConfig

      success
    end

    def setISNSConfig(address, port)
      @config.set_isns(address, port)
    end

    # Called for data (output) of commands:
    #  iscsiadm -m node -P 1
    #  iscsiadm -m session -P 1
    #
    # @param data [Array<String>] output of the executed command, one array entry per line
    def ScanDiscovered(data)
      data = deep_copy(data)
      ret = []
      target = ""
      portal = ""
      iface = ""
      dumped = true
      Builtins.y2milestone("Got data: %1", data)

      # Each entry starts with Target:, the other two values are optional
      # (except the first entry) and, if missing, are inherited from previous
      # entry. Therefore: Dump whatever is cached on Target: entry and once
      # again at the end. Example input in the test case.

      Builtins.foreach(data) do |row|
        row = Builtins.substring(row, Builtins.findfirstnotof(row, "\t "), 999)
        if Builtins.search(row, "Target:") != nil
          if !dumped
            # don't add Scope:Link IPv6 address
            ret << "#{portal} #{target} #{iface}" if !portal.start_with?("[fe80:")
          end
          target = Ops.get(Builtins.splitstring(row, " "), 1, "")
          dumped = false
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
          ret << "#{portal} #{target} #{iface}" if !portal.start_with?("[fe80:")
          dumped = true
        end
      end
      if !dumped
        # don't add Scope:Link IPv6 address
        ret << "#{portal} #{target} #{iface}" if !portal.start_with?("[fe80:")
      end

      Builtins.y2milestone("ScanDiscovered ret:%1", ret)
      deep_copy(ret)
    end

    # Read all discovered targets from the local nodes database, storing the result in the
    # {#discovered} attribute
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
      retcode = SCR.Execute(path(".target.bash"), "pgrep iscsid")
      Service.Stop("iscsid") if retcode == 0
      start_iscsid_initial
    end

    def start_iscsid_initial
      SCR.Execute(path(".target.bash"), "pgrep iscsid || iscsid")
      10.times do |i|
        Builtins.sleep(1 * 1000)
        cmd = SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m session"))
        Builtins.y2internal("iteration %1, retcode %2", i, cmd["exit"])
        # Both exit codes 0 and 21 may indicate success.
        # See discussion in bsc#1131049.
        if [0, 21].include?(cmd["exit"])
          Builtins.y2internal("Good response from daemon, exit.")
          break
        end
      end

      nil
    end

    # Get all connected targets storing the result in the #sessions attribute
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
          Builtins.sformat("mv %1 /etc/iscsi/initiatorname.yastbackup", file.shellescape)
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
          SCR.Execute(path(".target.bash_output"), "hostname -f | tr -d '\n'"),
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
    def checkInitiatorName(silent: false)
      ret = true
      file = "/etc/iscsi/initiatorname.iscsi"
      name_from_bios = getiBFT["iface.initiatorname"] || ""
      # if (size((map<string, any>)SCR::Read (.target.lstat, file)) == 0 || ((map<string, any>)SCR::Read (.target.lstat, file))["size"]:0==0){
      @initiatorname = Ops.get_string(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat(
            "grep -v '^#' %1 | grep InitiatorName | cut -d'=' -f2 | tr -d '\n'",
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
              "iscsi-iname -p iqn.%1.%2:01 | tr -d '\n'",
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
          if !silent
            Popup.Warning(
              _(
                "InitiatorName from iBFT and from <tt>/etc/iscsi/initiatorname.iscsi</tt>\n" \
                  "differ. The old initiator name will be replaced by the value of iBFT and a \n" \
                  "backup created. If you want to use a different initiator name, change it \n" \
                  "in the BIOS.\n"
              )
            )
          end
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

    # Logout from the target (ie. remove the corresponding session)
    #
    # This does not delete the target from nodes database. The name of the method is plain wrong
    # for historical reasons.
    #
    # To delete a record from the database of discovered targets, see {#removeRecord} instead.
    #
    # @return [Boolean] false if the logout operation reports any error or true if it succeeds (note
    #   {#sessions} gets refreshed in the latter case)
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

    # Delete the current node from the database of discovered targets
    #
    # It does not check whether the node is connected. Bear in mind the result in that case is
    # uncertain. According to our manual tests, if you try to delete a node upon which a session is
    # based, iscsiadm will refuse the request leaving the node entry in the database intact. On the
    # other hand iscsiadm manpage states the following. "Delete should not be used on a running
    # session. If it is iscsiadm will stop the session and then delete the record."
    #
    # @return [Boolean] whether the operation succeeded with no incidences
    def removeRecord
      Builtins.y2milestone("Remove record %1", @currentRecord)

      result = SCR.Execute(
        path(".target.bash_output"),
        GetAdmCmd(
          Builtins.sformat(
            "-m node -T %1 -p %2 -I %3 --op=delete",
            Ops.get(@currentRecord, 1, "").shellescape,
            Ops.get(@currentRecord, 0, "").shellescape,
            Ops.get(@currentRecord, 2, "").shellescape
          )
        )
      )
      Builtins.y2milestone(result.inspect)
      result["exit"].zero?
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
    # @param n1  [Hash]    iSCSI node values as hash
    # @param n2  [Hash]    iSCSI node values as hash
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
    # @param node_info [Hash]      iSCSI node values as hash
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
      !!find_session(check_ip)
    end

    # Find the current record in the list of sessions
    #
    # @param check_ip [Boolean] whether the ip address must be considered in the comparison
    # @return [String, nil] corresponding entry from #sessions or nil if not found
    def find_session(check_ip)
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
          return row
        end
      end

      nil
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
            "-m node -I %3 -T %1 -p %2 --op=update --name=node.conn[0].startup --value=%4",
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

    # Logs into the targets specified by iBFT
    def autoLogOn
      ret = true
      log.info "begin of autoLogOn function"
      if !getiBFT.empty?
        result = SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m fw -l"))
        ret = false if result["exit"] != 0

        # Note that fw discovery does not store persistent records in the node or discovery DB,
        # so this is likely only done for reporting purposes (writing the info to the YaST logs)
        log.info "Autologin into iBFT : #{result}"
        result = SCR.Execute(path(".target.bash_output"), GetAdmCmd("-m discovery -t fw"))
        log.info "iBFT discovery: #{result}"
      end
      ret
    end

    # Perform an iSCSI login operation into the specified target
    #
    # Modifies {#currentRecord}
    # @see #login_into_current
    #
    # @param target [Hash{String => String}] a hash with the mandatory keys "portal", "target" and
    #   "iface" and with the optional "authmethod", "username", "username_in", "password" and
    #   "password_in".
    def loginIntoTarget(target)
      target = deep_copy(target)
      @currentRecord = [
        Ops.get_string(target, "portal", ""),
        Ops.get_string(target, "target", ""),
        Ops.get_string(target, "iface", "")
      ]

      auth = Y2IscsiClient::Authentication.new_from_legacy(target)
      login_into_current(auth)
      true
    end

    # Perform an iSCSI login operation into the node described at {#currentRecord}
    #
    # @param auth [Y2IscsiClient::Authentication] auth information for the login operation
    # @param silent [Boolean] whether visual error reporting should be suppressed
    # @return [Boolean] whether the operation succeeded with no incidences
    def login_into_current(auth, silent: false)
      if auth.chap?
        setValue("node.session.auth.authmethod", "CHAP")
        setValue("node.session.auth.username", auth.username)
        setValue("node.session.auth.password", auth.password)
        if auth.by_initiator?
          setValue("node.session.auth.username_in", auth.username_in)
          setValue("node.session.auth.password_in", auth.password_in)
        end
      else
        setValue("node.session.auth.authmethod", "None")
      end

      ret = true
      output = SCR.Execute(
        path(".target.bash_output"),
        GetAdmCmd(
          Builtins.sformat(
            "-m node -I %3 -T %1 -p %2 --login",
            Ops.get(@currentRecord, 1, "").shellescape,
            Ops.get(@currentRecord, 0, "").shellescape,
            Ops.get(@currentRecord, 2, "").shellescape
          )
        )
      )

      Builtins.y2internal("output %1", output)

      # Only log the fact that the session is already present (not an error at all)
      # to avoid a popup for AutoYaST install (bsc#981693)
      if output["exit"] == 15
        Builtins.y2milestone("Session already present %1", output["stderr"] || "")
        ret = false
      # Report a warning (not an error) if login failed for other reasons
      # (also related to bsc#981693, warning popups usually are skipped)
      elsif output["exit"] != 0
        if silent
          Builtins.y2milestone("Target connection failed %1", output["stderr"] || "")
        else
          Report.Warning(_("Target connection failed.\n") + output["stderr"] || "")
        end
        ret = false
      end

      if !Mode.autoinst
        ret = setStartupStatus("onboot") && ret
      end
      ret
    end

    # Starts iscsi-related services if they are not running
    #
    # As a side effect, it also takes care of initializing the @iscsid_socket and @iscsiuio_socket
    # instance variables that are basic for other methods to work as expected.
    #
    # FIXME: The name gives a totally wrong impression on the method responsibilities and
    # functionality. It seems to suggest it should simply return the status of the services.
    #
    # @return [Boolean] true in all cases, which looks suspicious
    def getServiceStatus
      ret = true
      if Stage.initial
        load_modules
        # start daemon manually (systemd not available in inst-sys)
        start_services_initial
      else
        # find sockets (only in installed system)
        # throw exception if socket not found
        @iscsid_socket = Yast2::Systemd::Socket.find!("iscsid")
        @iscsiuio_socket = Yast2::Systemd::Socket.find!("iscsiuio")

        iscsi_service_stat = Service.active?("iscsi")
        iscsid_socket_stat = socketActive?(@iscsid_socket)
        iscsiuio_socket_stat = socketActive?(@iscsiuio_socket)

        log.info "Status of iscsi.service: #{iscsi_service_stat}, iscsid.socket: #{iscsid_socket_stat}, iscsiuio.socket: #{iscsiuio_socket_stat}"

        # if not running, start iscsi.service, iscsid.socket and iscsiuio.socket
        if !iscsid_socket_stat
          Service.Stop("iscsid") if Service.active?("iscsid")
          log.error "Cannot start iscsid.socket" if !socketStart(@iscsid_socket)
        end
        if !iscsiuio_socket_stat
          Service.Stop("iscsiuio") if Service.active?("iscsiuio")
          log.error "Cannot start iscsiuio.socket" if !socketStart(@iscsiuio_socket)
        end
        if !iscsi_service_stat && !Service.Start("iscsi")
          log.error "Cannot start iscsi.service"
        end
      end
      ret
    end

    # Stops immediately all iscsi-related services and sockets if those services are disabled and
    # there are no running sessions.
    #
    # NOTE: this only works in the installed system, it does nothing during installation.
    #
    # NOTE: this is reliable only if {#getServiceStatus} has been called before (since that's
    # the only way to initialize @iscsid_socket and @iscsiuio_socket). Not sure if that method
    # interdependency is intentional (looks dangerous).
    #
    # FIXME: The name gives a totally wrong impression on the method functionality. This method
    # is only useful to stop services, it never starts/enables/disables any service.
    #
    # @return [Boolean] true in all cases, which looks suspicious
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
        next if ifaces.include?(iface) # already added

        ifacepar << " " unless ifacepar.empty?
        ifacepar << "-I " << iface.shellescape
        ifaces << iface
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
      if retcode["stderr"].empty?
        ScanDiscovered(retcode["stdout"].split("\n")).each do |s|
          sl = Builtins.splitstring(s, "  ")
          iface_name = sl[2] || ""
          next if iface_name.empty? || ifaces.include?(iface_name)

          ifaces << iface_name
        end
      end
      Builtins.y2milestone("InitOffloadCard ifaces:%1", ifaces)
      if ifaces.size > 1
        ret = "all"
      elsif @iface_eth.include?(ifaces.first)
        ret = ifaces.first || "default"
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
      if @offload_valid.nil?
        init = true
        InitIfaceFile()
        InitOffloadValid()
      end

      entries = {}
      @offload_valid.each do |i, cards|
        cards.each do |card|
          next if card[0].nil? || card[0].empty?

          entries[card[2]] = card_label(card, @offload[i][1])
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
        # Entry for "default"
        Item(Id(@offload[0][0]), @offload[0][1], @offload_card == @offload[0][0])
      ]
      if @offload_valid.any?
        # Entry for "all"
        ret << Item(
          Id(@offload[1][0]), @offload[1][1], @offload_card == @offload[1][0]
        )
      end
      # Entries for the valid cards
      ret.concat(
        @iface_eth.map { |e| Item(Id(e), entries[e], @offload_card == e) }
      )
      Builtins.y2milestone("GetOffloadItems ret:%1", ret)
      deep_copy(ret)
    end

    # Modules to use for all the cards detected in the system and that support hardware
    # offloading, no matter whether those cards are indeed configured
    #
    # The module to use for each card is determined by the fourth element of the
    # corresponding entry at @offload.
    #
    # @return [Array<String>]
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

    # @return [Array<String>]
    def GetDiscoveryCmd(ip, port, use_fw: false, only_new: false)
      Builtins.y2milestone("GetDiscoveryCmd ip:%1 port:%2 fw:%3 only new:%4",
        ip, port, use_fw, only_new)
      command = ["iscsiadm", "-m", "discovery", "-P", "1"]
      isns_info = useISNS
      if isns_info["use"]
        command << "-t" << "isns"
      else
        ifs = GetDiscIfaces()
        Builtins.y2milestone("ifs=%1", ifs)
        ifs = ifs.each_with_object([]) { |s, res| res << "-I" << s }
        Builtins.y2milestone("ifs=%1", ifs)
        tgt = "st"
        tgt = "fw" if use_fw
        command << "-t" << tgt
        command.concat(ifs)
      end

      command << "-p" << "#{ip}:#{port}"
      command << "-o" << "new" if only_new

      Builtins.y2milestone("GetDiscoveryCmd %1", command)
      command
    end

    # Whether the system contains any offload card that would need the iscsiuio user-space
    # I/O driver (see bsc#1194432)
    #
    # No matter where the card is configured or not
    #
    # @return [Boolean]
    def iscsiuio_relevant?
      (ISCSIUIO_MODULES & GetOffloadModules()).any?
    end

    # Loads the kernel modules needed to configure the iscsi client
    def load_modules
      ModuleLoading.Load("iscsi_tcp", "", "", "", false, true)
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
    publish :function => :setISNSConfig, :type => "void (string, string)"
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
    publish :function => :getCurrentNodeValues, :type => "map <string, any> ()"
    publish :function => :iBFT?, :type => "boolean (map <string, any>)"

  private

    def InitOffloadValid
      @offload_valid = potential_offload_cards
      card_names = @offload_valid.values.flatten(1).map(&:first)
      offload_res = configure_offload_engines(card_names)

      # Filter only those cards for which we have a hwaddr value in offload_res
      @offload_valid.values.each do |cards|
        cards.select! do |card|
          card_res = offload_res[card[0]]
          card_res["exit"].zero? && card_res["hwaddr"]
        end
      end
      Builtins.y2milestone("GetOffloadItems offload_res:%1", offload_res)
      Builtins.y2milestone("GetOffloadItems offload_valid:%1", @offload_valid)

      # Sync the MAC with the hwaddr value from offload_res
      @offload_valid.values.each do |cards|
        cards.each do |card|
          dev_name = card[0]
          card[1] = offload_res[dev_name]["hwaddr"]
        end
      end
      Builtins.y2milestone("GetOffloadItems offload_valid:%1", @offload_valid)

      @offload_valid.values.each do |cards|
        cards.each do |card|
          card << ip_addr(card[0])
        end
      end
      Builtins.y2milestone("GetOffloadItems offload_valid:%1", @offload_valid)
    end

    # List of modules for the given card description
    #
    # The card description must be a hash in the format returned by the
    # probe.netcard agent (ie. libhd, a.k.a. hwinfo).
    #
    # Such a netcard hash contains a "drivers" entry which is an array in which
    # every element represents a driver.
    #
    # Such a driver is represented by a hash with the following structure:
    # {
    #   "active"   => [Boolean] whether the corresponding modules are already loaded
    #   "modprobe" => [Boolean] whether modprobe or insmod is to be used for loading
    #   "modules   => [Array<Array<String>>] list of modules, with this structure:
    #                 [ [<modname1>, <modargs1>], [<modname2>, <modargs2>], ... ]
    # }
    #
    # @param card [Hash] description of a netcard as returned by the probe.netcard agent
    # @return [Array<String>] names of modules
    def netcard_modules(card)
      return [] unless card.key?("drivers")

      card["drivers"].flat_map { |d| d["modules"].map(&:first) }
    end

    # Cards in the system that match with the types described by @offload
    #
    # return [Hash] cards grouped by type, in the same format used by @offload_valid
    #   (with a small exception, the cards don't include a field for the IP address)
    def potential_offload_cards
      # Store into hw_mods information about all the cards in the system
      cards = SCR.Read(path(".probe.netcard"))
      hw_mods = cards.map do |c|
        Builtins.y2milestone("GetOffloadItems card:%1", c)
        hw_mod = {
          "modules" => netcard_modules(c),
          "iface"   => c["dev_name"] || "",
          "macaddr" => Ops.get_string(c, ["resource", "hwaddr", 0, "addr"], "")
        }
        Builtins.y2milestone("GetOffloadItems cinf:%1", hw_mod)
        hw_mod
      end

      result = {}
      @offload.each.with_index do |offload_entry, idx|
        modules = offload_entry[2]
        # Ignore this offload entry if it does not specify any module to do the match
        next if modules.empty?

        hw_mods.each do |hw|
          # Ignore this card unless it has some module in common with the offload entry
          next if (modules & hw["modules"]).empty?

          Builtins.y2milestone("GetOffloadItems l:%1", offload_entry)
          Builtins.y2milestone("GetOffloadItems valid:%1", hw)
          result[idx] ||= []
          result[idx] << [
            hw["iface"],
            hw["macaddr"], # In fact, this is going to be overwritten at a later point
            "#{hw["iface"]}-#{offload_entry[3].first}"
          ]
        end
      end

      result
    end

    # Configures iSCSI offload engines for the given cards
    #
    # Tries to create an open-iscsi interface definition for each of the given cards.
    #
    # @param cards [Array<String>] list of interface names
    # @return [Hash{String => Hash}] results of the operation, keys are the names of the interfaces
    #   and values the corresponding result as a hash with three fields: "exit" (0 means the
    #   definition was created), "hwaddr" and "ntype".
    def configure_offload_engines(cards)
      offload_res = {}

      cards.each do |dev_name|
        cmd = "#{OFFLOAD_SCRIPT} #{dev_name.shellescape} | grep ..:..:..:.." # grep for lines containing MAC address
        Builtins.y2milestone("GetOffloadItems cmd:%1", cmd)
        out = SCR.Execute(path(".target.bash_output"), cmd)
        # Example for output if offload is supported on interface:
        # cmd: iscsi_offload eth2
        # out: $["exit":0, "stderr":"", "stdout":"00:00:c9:b1:bc:7f ip \n"]
        cmd2 = "#{OFFLOAD_SCRIPT} #{dev_name.shellescape}"
        result = SCR.Execute(path(".target.bash_output"), cmd2)
        Builtins.y2milestone("GetOffloadItems iscsi_offload out:%1", result)

        offload_res[dev_name] = {}
        offload_res[dev_name]["exit"] = out["exit"]
        next unless out["exit"].zero?

        sl = Builtins.splitstring(out["stdout"], " \n")
        offload_res[dev_name]["hwaddr"] = sl[0]
        offload_res[dev_name]["ntype"] = sl[1]
      end

      offload_res
    end

    # Current IP address of the given network interface
    def ip_addr(dev_name)
      cmd = "LC_ALL=POSIX ifconfig #{dev_name.shellescape}" # FIXME: ifconfig is deprecated
      Builtins.y2milestone("GetOffloadItems cmd:%1", cmd)
      out = SCR.Execute(path(".target.bash_output"), cmd)
      Builtins.y2milestone("GetOffloadItems out:%1", out)

      # Search for lines containing "init addr", means IPv4 address.
      # Regarding the IPv6 support there are no changes needed here because
      # the IP address is not used farther.
      line = out["stdout"].split("\n").find do |ln|
        Builtins.search(ln, "inet addr:") != nil
      end
      line ||= ""
      Builtins.y2milestone("GetOffloadItems line:%1", line)

      ipaddr = "unknown"
      if !line.empty?
        line = Builtins.substring(line, Builtins.search(line, "inet addr:") + 10)
        Builtins.y2milestone("GetOffloadItems line:%1", line)
        ipaddr = Builtins.substring(line, 0, Builtins.findfirstof(line, " \t"))
      end

      ipaddr
    end

    def card_label(card, type_label)
      dev_name = card[0]
      hwaddr = card[1]
      hwaddr = nil if hwaddr&.empty?

      [dev_name, hwaddr, type_label].compact.join(" - ")
    end
  end

  IscsiClientLib = IscsiClientLibClass.new
  IscsiClientLib.main
end
