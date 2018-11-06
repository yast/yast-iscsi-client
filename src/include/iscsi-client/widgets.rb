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
# File:	clients/iscsi-client.ycp
# Package:	Configuration of iscsi-client
# Summary:	Main file
# Authors:	Michal Zugec <mzugec@suse.cz>
#
# $Id$
#
# Main file for iscsi-client configuration. Uses all other files.
module Yast
  module IscsiClientWidgetsInclude
    def initialize_iscsi_client_widgets(include_target)
      textdomain "iscsi-client"
      Yast.import "IP"

      @stat = false
      @curr_rec = []
      @bg_finish = false
    end

    # string initiatorname="";
    # function for run command in background
    def runInBg(command)
      @bg_finish = false
      Builtins.y2milestone("Start command %1 in background", command)
      stdout = []
      return_code = nil
      started = Convert.to_boolean(
        SCR.Execute(path(".background.run_output_err"), command)
      )
      if !started
        Builtins.y2error("Cannot run command")
        @stat = false
        return []
      end
      time_spent = 0
      cont_loop = true
      script_time_out = 10000
      sleep_step = 20
      while cont_loop &&
          Convert.to_boolean(SCR.Read(path(".background.output_open")))
        if Ops.greater_or_equal(time_spent, script_time_out)
          Popup.Error(_("Command timed out"))
          cont_loop = false
        end
        time_spent = Ops.add(time_spent, sleep_step)
        Builtins.sleep(sleep_step)
      end
      Builtins.y2milestone("Time spent: %1 msec", time_spent)
      stdout = Convert.convert(
        SCR.Read(path(".background.newout")),
        :from => "any",
        :to   => "list <string>"
      )
      Builtins.y2milestone("Output: %1", stdout)
      if cont_loop
        return_code = Convert.to_integer(SCR.Read(path(".background.status")))
        Builtins.y2milestone("Return: %1", return_code)
        if return_code != 0
          @stat = false
          error = Ops.get(
            Convert.convert(
              SCR.Read(path(".background.newerr")),
              :from => "any",
              :to   => "list <string>"
                            ),
            0,
            ""
                          )
          Builtins.y2error("Error: %1", error)
          Popup.Error(error)
        else
          @stat = true
        end
      else
        # killing the process if it still runs
        if Convert.to_boolean(SCR.Read(path(".background.output_open")))
          SCR.Execute(path(".background.kill"), "")
        end
      end
      @bg_finish = true
      deep_copy(stdout)
    end

    # validation for authentication dialog entry
    def checkAuthEntry
      Builtins.y2milestone("Check entries for authentication")
      ret = true
      auth_none = Convert.to_boolean(UI.QueryWidget(Id(:auth_none), :Value))
      auth_in = Convert.to_boolean(UI.QueryWidget(Id(:auth_in), :Value))
      auth_out = Convert.to_boolean(UI.QueryWidget(Id(:auth_out), :Value))
      user_in = Builtins.tostring(UI.QueryWidget(Id(:user_in), :Value))
      pass_in = Builtins.tostring(UI.QueryWidget(Id(:pass_in), :Value))
      user_out = Builtins.tostring(UI.QueryWidget(Id(:user_out), :Value))
      pass_out = Builtins.tostring(UI.QueryWidget(Id(:pass_out), :Value))
      if auth_none
        return true
      else
        if auth_in
          if Builtins.size(user_in) == 0
            Popup.Error(_("Insert the username."))
            UI.SetFocus(Id(:user_in))
            return false
          end
          if Builtins.size(pass_in) == 0
            Popup.Error(_("Insert the password."))
            UI.SetFocus(Id(:pass_in))
            return false
          end
        end
        if auth_out
          if Builtins.size(user_out) == 0
            Popup.Error(_("Insert the username."))
            UI.SetFocus(Id(:user_out))
            return false
          end
          if Builtins.size(pass_out) == 0
            Popup.Error(_("Insert the password."))
            UI.SetFocus(Id(:pass_out))
            return false
          end
        end
      end
      ret
    end

    # init table of connected sessions
    def initConnectedTable(key)
      if IscsiClientLib.readSessions == false
        Popup.Error(_("Error While Connecting iscsid"))
      end
      row_current = Convert.to_integer(UI.QueryWidget(:connected, :CurrentItem))
      items = []
      row = 0
      Builtins.foreach(IscsiClientLib.sessions) do |s|
        IscsiClientLib.currentRecord = Builtins.splitstring(s, " ")
        items = Builtins.add(
          items,
          Item(
            Id(row),
            Ops.get(IscsiClientLib.currentRecord, 2, ""),
            Ops.get(IscsiClientLib.currentRecord, 0, ""),
            Ops.get(IscsiClientLib.currentRecord, 1, ""),
            IscsiClientLib.getStartupStatus
          )
        )
        row = Ops.add(row, 1)
      end
      UI.ChangeWidget(Id(:connected), :Items, items)
      UI.ChangeWidget(:connected, :CurrentItem, row_current)
      UI.SetFocus(Id(:connected))

      nil
    end

    # get record identificator from selected row
    def setRecord
      IscsiClientLib.currentRecord = []
      sel_item = UI.QueryWidget(Id(:connected), :CurrentItem)
      if sel_item != nil
        current = Builtins.tointeger(sel_item)
        IscsiClientLib.currentRecord = Builtins.splitstring(
          Ops.get(IscsiClientLib.sessions, current, ""),
          " "
        )
        #	 record = deletechars(record, "[]");
      elsif Ops.greater_than(Builtins.size(IscsiClientLib.sessions), 0)
        IscsiClientLib.currentRecord = Builtins.splitstring(
          Ops.get(IscsiClientLib.sessions, 0, ""),
          " "
        )
      end
      deep_copy(IscsiClientLib.currentRecord)
    end

    # handle for table of connected sessions
    def handleConnectedTable(key, event)
      event = deep_copy(event)
      if Ops.get_string(event, "EventReason", "") == "Activated"
        record = []
        case Ops.get_symbol(event, "ID")
          when :add
            # add a new target, discovery
            # goto DiscAuthDialog("client")) ()
            Builtins.y2milestone("Goto dicovered authentication dialog")
            return :add
          when :del
            # delete (logout from) connected target
            record = setRecord
            if Ops.greater_than(Builtins.size(record), 0)
              if Popup.ContinueCancel(
                  _("Really log out from the selected target?")
                )
                if !IscsiClientLib.deleteRecord
                  Popup.Error(
                    _(
                      "Error occurred while logging out from the selected target."
                    )
                  )
                else
                  Builtins.y2milestone("Delete record %1", record)
                  initConnectedTable("")
                end
              end
            else
              Popup.Error(_("No record found."))
            end
          when :edit
            record = setRecord
            return :edit
        end
      end
      # if nothing selected - disable some buttons, otherwise enable them
      if setRecord == []
        UI.ChangeWidget(Id(:del), :Enabled, false)
        UI.ChangeWidget(Id(:edit), :Enabled, false)
      else
        UI.ChangeWidget(Id(:del), :Enabled, true)
        UI.ChangeWidget(Id(:edit), :Enabled, true)
      end
      nil
    end

    def initISNS(key)
      Builtins.foreach(IscsiClientLib.getConfig) do |row|
        if Ops.get_string(row, "name", "") == "isns.address"
          UI.ChangeWidget(
            :isns_address,
            :Value,
            Ops.get_string(row, "value", "")
          )
        end
        if Ops.get_string(row, "name", "") == "isns.port"
          UI.ChangeWidget(:isns_port, :Value, Ops.get_string(row, "value", ""))
        end
      end
      UI.ChangeWidget(:isns_port, :ValidChars, "0123456789")

      nil
    end

    def validateISNS(key, event)
      event = deep_copy(event)
      address = Convert.to_string(UI.QueryWidget(:isns_address, :Value))
      port = Convert.to_string(UI.QueryWidget(:isns_port, :Value))
      return true if Builtins.size(address) == 0 && Builtins.size(port) == 0
      if !IP.Check(address)
        Popup.Error(_("No valid IP address"))
        UI.SetFocus(:isns_address)
        return false
      end
      if Builtins.size(port) == 0
        Popup.Error(_("Port field cannot be empty"))
        UI.SetFocus(:isns_port)
        return false
      end
      true
    end


    def storeISNS(key, event)
      event = deep_copy(event)
      address = Convert.to_string(UI.QueryWidget(:isns_address, :Value))
      port = Convert.to_string(UI.QueryWidget(:isns_port, :Value))
      found_addr = false
      found_port = false
      tmp_config = []

      Builtins.foreach(IscsiClientLib.getConfig) do |row|
        if Ops.get_string(row, "name", "") == "isns.address"
          Ops.set(row, "value", address)
          found_addr = true
        end
        if Ops.get_string(row, "name", "") == "isns.port"
          Ops.set(row, "value", port)
          found_port = true
        end
        if (Ops.get_string(row, "name", "") == "isns.address" ||
            Ops.get_string(row, "name", "") == "isns.port") &&
            Ops.greater_than(Builtins.size(address), 0) &&
              Ops.greater_than(Builtins.size(port), 0) ||
            Ops.get_string(row, "name", "") != "isns.address" &&
              Ops.get_string(row, "name", "") != "isns.port"
          tmp_config = Builtins.add(tmp_config, row)
        end
      end
      if Ops.greater_than(Builtins.size(address), 0) &&
          Ops.greater_than(Builtins.size(port), 0)
        if !found_addr
          tmp_config = Builtins.add(
            tmp_config,
            "name"    => "isns.address",
            "value"   => address,
            "kind"    => "value",
            "type"    => 1,
            "comment" => ""
          )
        end
        if !found_port
          tmp_config = Builtins.add(
            tmp_config,
            "name"    => "isns.port",
            "value"   => port,
            "kind"    => "value",
            "type"    => 1,
            "comment" => ""
          )
        end
      end

      IscsiClientLib.setConfig(tmp_config)
      IscsiClientLib.oldConfig
      nil
    end



    def initInitName(key)
      Builtins.y2milestone("initiatorname %1", IscsiClientLib.initiatorname)
      UI.ChangeWidget(:initiator_name, :Value, IscsiClientLib.initiatorname)
      UI.ChangeWidget(:offload_card, :Items, IscsiClientLib.GetOffloadItems)
      UI.ChangeWidget(:offload_card, :Value, IscsiClientLib.GetOffloadCard)
      Builtins.y2milestone("OffloadCard %1", IscsiClientLib.GetOffloadCard)
      if Ops.greater_than(
        Builtins.size(
          Ops.get_string(IscsiClientLib.getiBFT, "iSCSI_INITIATOR_NAME", "")
        ),
        0
        )
        UI.ChangeWidget(:initiator_name, :Enabled, false)
        UI.ChangeWidget(:write, :Enabled, false)
      end

      nil
    end

    def validateInitName(key, event)
      event = deep_copy(event)
      #  Targets definitions start with "Target" and the target name.
      #  The target name must be a globally unique name, the iSCSI
      #  standard defines the "iSCSI Qualified Name" as follows:
      #
      #  iqn.yyyy-mm.reversed domain name[:identifier]
      #
      #  "yyyy-mm" is the date at which the domain is valid and the identifier
      #  is freely selectable. For further details please check the iSCSI spec.

      i_name = Convert.to_string(UI.QueryWidget(:initiator_name, :Value))

      # name not changed at all or already saved after checking it
      if IscsiClientLib.initiatorname == i_name
        return true
      end

      # regexp for "yyyy-mm."
      reg1 = "[[:digit:]]{4}-[[:digit:]]{2}."
      # regexp for "cz.suse" or just "suse", "cz.su-se"
      reg2 = "[[:alnum:].:-]*"

      correct = Builtins.regexpmatch(
        i_name,
        Builtins.sformat("^iqn.%1%2$", reg1, reg2)
      ) ||
        Builtins.regexpmatch(i_name, Builtins.sformat("^eui.%1%2$", reg1, reg2))

      if !correct
        go_on = Popup.YesNoHeadline(_("Incorrect Initiator Name"),
          _(
            "\n" +
            "The correct syntax is\n" +
            "iqn.yyyy-mm.reversed.domain.name[:identifier]\n" +
            "or eui.yyyy-mm.reversed.domain.name[:identifier]\n" +
            "\n" +
            "Example:\n" +
            "iqn.2007-04.cz.server:storage.disk.sdb\n" +
            "\n" +
            "Do you want to use the name?\n"
          )
        )
        return go_on
      else
        return true
      end
    end


    def storeInitName(key, event)
      event = deep_copy(event)
      if Convert.to_string(UI.QueryWidget(:initiator_name, :Value)) !=
          IscsiClientLib.initiatorname
        # write initiatorname
        IscsiClientLib.writeInitiatorName(
          Convert.to_string(UI.QueryWidget(:initiator_name, :Value))
        )
        if Stage.initial
          IscsiClientLib.restart_iscsid_initial
        else
          Service.Restart("iscsid")
        end
        Builtins.y2milestone(
          "write initiatorname %1",
          IscsiClientLib.initiatorname
        )
      end
      if Convert.to_string(UI.QueryWidget(:offload_card, :Value)) !=
          IscsiClientLib.GetOffloadCard
        IscsiClientLib.SetOffloadCard(
          Convert.to_string(UI.QueryWidget(:offload_card, :Value))
        )
        Builtins.y2milestone("OffloadCard %1", IscsiClientLib.GetOffloadCard)
      end
      nil
    end

    def handleOffload(key, event)
      event = deep_copy(event)
      if event["EventReason"] || "" == "ValueChanged" &&
          event["ID"] || :none == :offload_card
        if Convert.to_string(UI.QueryWidget(:offload_card, :Value)) !=
            IscsiClientLib.GetOffloadCard
          IscsiClientLib.SetOffloadCard(
            Convert.to_string(UI.QueryWidget(:offload_card, :Value))
          )
          Builtins.y2milestone(
            "handleOffload OffloadCard %1",
            IscsiClientLib.GetOffloadCard
          )
        end
      end
      nil
    end

    # ***************** iBFT table **************************
    def initiBFT(key)
      items = []
      Builtins.foreach(IscsiClientLib.hidePassword(IscsiClientLib.getiBFT)) do |key2, value|
        items = Builtins.add(items, Item(Id(Builtins.size(items)), key2, value))
      end
      UI.ChangeWidget(:bios, :Items, items)

      nil
    end
    # ***************** add table ***************************

    # set incoming widget status
    # void setAuthIn(boolean status){
    #  UI::ChangeWidget(`id(`user_in),`Enabled, status );
    #  UI::ChangeWidget(`id(`pass_in),`Enabled, status );
    #  UI::ChangeWidget(`id(`auth_in),`Value, status );
    #  if(status) UI::ChangeWidget(`id(`auth_none),`Value, !status );
    # }

    # set outgoing widget status
    # void setAuthOut(boolean status){
    #  UI::ChangeWidget(`id(`user_out),`Enabled, status );
    #  UI::ChangeWidget(`id(`pass_out),`Enabled, status );
    #  UI::ChangeWidget(`id(`auth_out),`Value, status );
    #  if(status) UI::ChangeWidget(`id(`auth_none),`Value, !status );
    # }

    # disable both incoming and outgoing
    def initDiscAuth(key)
      nil
    end

    def initConnAuth(key)
      # setAuthIn(false);
      # setAuthOut(false);
      auth = IscsiClientLib.getNode
      if Ops.greater_than(Builtins.size(auth), 0)
        UI.ChangeWidget(
          Id(:user_in),
          :Value,
          Ops.get_string(auth, "username_in", "")
        )
        UI.ChangeWidget(
          Id(:pass_in),
          :Value,
          Ops.get_string(auth, "password_in", "")
        )
        #   if ((size(auth["username_in"]:"")>0)&&(size(auth["password_in"]:"")>0)) setAuthOut(true);
        UI.ChangeWidget(
          Id(:user_out),
          :Value,
          Ops.get_string(auth, "username", "")
        )
        UI.ChangeWidget(
          Id(:pass_out),
          :Value,
          Ops.get_string(auth, "password", "")
        )
        #   if ((size(auth["username"]:"")>0)&&(size(auth["password"]:"")>0)) setAuthOut(true);
      end
      startup = IscsiClientLib.getStartupStatus
      if Ops.greater_than(Builtins.size(startup), 0)
        UI.ChangeWidget(Id("startup"), :Value, startup)
      end

      nil
    end
    # handle for enable/disable widgets in authentication dialog
    def handleDiscAuth(key, event)
      event = deep_copy(event)
      if Ops.get_string(event, "EventReason", "") == "ValueChanged"
        status = false
        case Ops.get_symbol(event, "ID")
          when :auth_none
            status = Convert.to_boolean(UI.QueryWidget(Id(:auth_none), :Value))
          when :auth_in
            status = Convert.to_boolean(UI.QueryWidget(Id(:auth_in), :Value))
          when :auth_out
            status = Convert.to_boolean(UI.QueryWidget(Id(:auth_out), :Value))
        end
      end
      nil
    end

    def validateDiscAuth(key, event)
      event = deep_copy(event)
      checkAuthEntry
    end
    # *******************Server Location ***********************

    def initServerLocation(key)
      isns_info = IscsiClientLib.useISNS()
      Builtins.y2milestone("is iSNS %1", isns_info["use"])
      if isns_info["use"]
        UI.ChangeWidget(:hostname, :Enabled, false)
        UI.ChangeWidget(:port, :Enabled, false)
      end

      nil
    end

    # do discovery to selected portal
    def validateServerLocation(key, event)
      ip = Builtins.tostring(UI.QueryWidget(:hostname, :Value))
      ip.strip!

      port = Builtins.tostring(UI.QueryWidget(:port, :Value))
      isns_info = IscsiClientLib.useISNS

      if !isns_info["use"]
        # validate ip
        if ip.empty?
          Popup.Error(_("Insert the IP address."))
          UI.SetFocus(:ip)
          return false
        end
        if !IP.Check(ip)
          # check for valid host name
          result = SCR.Execute(path(".target.bash_output"),
            "LC_ALL=POSIX host #{ip}")
          Builtins.y2milestone("Cmd: host %1, result: %2", ip, result)
          output = result["stdout"] || ""

          if (result["exit"] != 0)
            Popup.Error(_("Please check IP address resp. host name.\n") + output.to_s + (result["stderr"]).to_s)
            UI.SetFocus(:hostname)
            return false
          elsif !output.empty?
            # take only first line of 'host' output because with IPv6
            # there might be several lines
            ip_info = output.split("\n").first
            ip = ip_info.split(" ").last
          end
        end
        # validate port number
        if port.empty?
          Popup.Error(_("Insert the port."))
          UI.SetFocus(:port)
          return false
        end
      else
        # use iSNS (ip and port already validated in validateISNS)
        ip = isns_info["address"] || ""
        port = isns_info["port"] || ""
      end

      if IP.Check6(ip)
       ip = "[#{ip}]" # brackets needed around IPv6
      end

      # store /etc/iscsi/iscsi.conf
      IscsiClientLib.getConfig

      auth_none = Convert.to_boolean(UI.QueryWidget(Id(:auth_none), :Value))
      user_in = Builtins.tostring(UI.QueryWidget(Id(:user_in), :Value))
      pass_in = Builtins.tostring(UI.QueryWidget(Id(:pass_in), :Value))
      user_out = Builtins.tostring(UI.QueryWidget(Id(:user_out), :Value))
      pass_out = Builtins.tostring(UI.QueryWidget(Id(:pass_out), :Value))
      auth_in = !auth_none && Ops.greater_than(Builtins.size(user_in), 0) &&
        Ops.greater_than(Builtins.size(pass_in), 0)
      auth_out = !auth_none && Ops.greater_than(Builtins.size(user_out), 0) &&
        Ops.greater_than(Builtins.size(pass_out), 0)

      if auth_none
        user_in = ""
        pass_in = ""
        user_out = ""
        pass_out = ""
      end
      if !auth_in
        user_in = ""
        pass_in = ""
      end
      if !auth_out
        user_out = ""
        pass_out = ""
      end

      # temporarily write authentication data to /etc/iscsi/iscsi.conf
      IscsiClientLib.saveConfig(user_in, pass_in, user_out, pass_out)

      @bg_finish = false

      # Check @current_tab (dialogs.rb) here. If it's "client", i.e. the
      # 'Add' button at 'Connected Targets' is used, create discovery
      # command with option --new. The start-up mode for already connected
      # targets won't change then (fate #317874, bnc #886796).
      option_new = (@current_tab == "client")

      command = IscsiClientLib.GetDiscoveryCmd(ip, port,
        use_fw:   false,
        only_new: option_new)
      trg_list = runInBg(command)
      while !@bg_finish

      end
      if Builtins.size(trg_list) == 0
        command = IscsiClientLib.GetDiscoveryCmd(ip, port,
          use_fw:   true,
          only_new: option_new)
        trg_list = runInBg(command)
        while !@bg_finish

        end
      end
      IscsiClientLib.targets = IscsiClientLib.ScanDiscovered(trg_list)
      # restore saved config
      IscsiClientLib.oldConfig

      @stat
    end


    # ********************* discovered table *******************

    # enable [ connect, delete ] buttons only for not connected items
    def setDiscoveredButtons
      params = []
      selected = UI.QueryWidget(:discovered, :CurrentItem)
      if selected != nil
        params = Builtins.splitstring(
          Ops.get(IscsiClientLib.discovered, Builtins.tointeger(selected), ""),
          " "
        )
      else
        params = []
      end
      IscsiClientLib.currentRecord = [
        Ops.get(Builtins.splitstring(Ops.get(params, 0, ""), ","), 0, ""),
        Ops.get(params, 1, ""),
        Ops.get(params, 2, "")
      ]
      if params == [] || IscsiClientLib.connected(true)
        UI.ChangeWidget(Id(:connect), :Enabled, false)
        UI.ChangeWidget(Id(:delete), :Enabled, false)
      else
        UI.ChangeWidget(Id(:connect), :Enabled, true)
        UI.ChangeWidget(Id(:delete), :Enabled, true)
      end

      nil
    end

    # initialize widget with discovered targets
    def initDiscoveredTable(key)
      items = []
      row = 0
      Builtins.foreach(IscsiClientLib.getDiscovered) do |s|
        IscsiClientLib.currentRecord = Builtins.splitstring(s, " ")
        #        string record = deletechars(row_in_string[0]:"", "[]");
        items = Builtins.add(
          items,
          Item(
            Id(row),
            Ops.get(IscsiClientLib.currentRecord, 2, ""),
            Ops.get(IscsiClientLib.currentRecord, 0, ""),
            Ops.get(IscsiClientLib.currentRecord, 1, ""),
            IscsiClientLib.connected(true) ? _("True") : _("False")
          )
        )
        row = Ops.add(row, 1)
      end
      UI.ChangeWidget(Id(:discovered), :Items, items)
      UI.SetFocus(Id(:discovered))
      setDiscoveredButtons

      nil
    end

    # handling widget with discovered targets
    def handleDiscoveredTable(key, event)
      event = deep_copy(event)
      params = []
      selected = UI.QueryWidget(:discovered, :CurrentItem)
      if selected != nil
        params = Builtins.splitstring(
          Ops.get(IscsiClientLib.discovered, Builtins.tointeger(selected), ""),
          " "
        )
      else
        params = []
      end
      IscsiClientLib.currentRecord = [
        Ops.get(Builtins.splitstring(Ops.get(params, 0, ""), ","), 0, ""),
        Ops.get(params, 1, ""),
        Ops.get(params, 2, "default")
      ]
      #    params = curr_rec;
      if Ops.get_string(event, "EventReason", "") == "Activated"
        # connect new target
        if Ops.get(event, "ID") == :connect
          # check if not already connected
          if IscsiClientLib.connected(false) == true
            if !Popup.AnyQuestion(
              Label.WarningMsg,
              _(
                "The target with this TargetName is already connected. Make sure that multipathing is enabled to prevent data corruption."
              ),
              _("Continue"),
              _("Cancel"),
              :focus_yes
              )
              return nil
            end
          end

          # goto ConnAuthDialog("discovered") (initDiscAuth)
          return :conn
        end
        # discovery target ConnAuthDialog("client") (initDiscAuth)
        return :disc if Ops.get(event, "ID") == :discovery
        # delete connected item
        if Ops.get(event, "ID") == :delete
          if params == [] || !IscsiClientLib.connected(true)
            cmd = IscsiClientLib.GetAdmCmd(
              Builtins.sformat(
                "-m node -T %1 -p %2 -I %3 --op=delete",
                Ops.get(params, 1, ""),
                Ops.get(params, 0, ""),
                Ops.get(params, 2, "")
              )
            )
            Builtins.y2milestone(
              "%1",
              SCR.Execute(path(".target.bash_output"), cmd, {})
            )
            IscsiClientLib.readSessions
            initDiscoveredTable("")
            if selected != nil
              params = Builtins.splitstring(
                Ops.get(
                  IscsiClientLib.discovered,
                  Builtins.tointeger(selected),
                  ""
                ),
                " "
              )
            else
              params = []
            end
          end
        end
      end
      setDiscoveredButtons
      nil
    end

    #******************* target table *************************

    # initialize dialog for all targets from portal (connected/disconnected)
    def initTargetTable(key)
      items = []
      row = 0
      Builtins.foreach(IscsiClientLib.targets) do |s|
        IscsiClientLib.currentRecord = Builtins.splitstring(s, " ")
        items = Builtins.add(
          items,
          Item(
            Id(row),
            Ops.get(IscsiClientLib.currentRecord, 2, ""),
            Ops.get(IscsiClientLib.currentRecord, 0, ""),
            Ops.get(IscsiClientLib.currentRecord, 1, ""),
            IscsiClientLib.connected(true) ? _("True") : _("False")
          )
        )
        row = Ops.add(row, 1)
      end
      UI.ChangeWidget(Id(:targets), :Items, items)
      UI.SetFocus(Id(:targets))

      nil
    end

    # handle dialog for all targets from portal (connected/disconnected) - only connect button ;)
    def handleTargetTable(key, event)
      event = deep_copy(event)
      #enable/disable connect button according target is or not already connected
      items = Convert.convert(
        UI.QueryWidget(:targets, :Items),
        :from => "any",
        :to   => "list <term>"
      )
      if Ops.get_string(
        Ops.get(
          items,
          Convert.to_integer(UI.QueryWidget(:targets, :CurrentItem))
        ),
        3,
        ""
        ) ==
          _("True")
        UI.ChangeWidget(:connect, :Enabled, false)
      else
        UI.ChangeWidget(:connect, :Enabled, true)
      end


      if Ops.get_string(event, "EventReason", "") == "Activated"
        if Ops.get(event, "ID") == :connect
          # check if is not already connected
          IscsiClientLib.currentRecord = Builtins.splitstring(
            Ops.get(
              IscsiClientLib.targets,
              Convert.to_integer(UI.QueryWidget(:targets, :CurrentItem)),
              ""
            ),
            " "
          )
          if IscsiClientLib.connected(true) == true
            Popup.Error(_("The target is already connected."))
          else
            # check if not already connected
            if IscsiClientLib.connected(false) == true
              if !Popup.AnyQuestion(
                Label.WarningMsg,
                _(
                  "The target with this TargetName is already connected. Make sure that multipathing is enabled to prevent data corruption."
                ),
                _("Continue"),
                _("Cancel"),
                :focus_yes
                )
                return nil
              end
            end

            # goto ConnAuthDialog("discovered") (initDiscAuth())
            return :conn_auth
          end
        end
      end
      nil
    end

    #***************** connection autentication *******************

    # login to target with authentication
    def validateConnAuth(key, event)
      event = deep_copy(event)
      auth_none = Convert.to_boolean(UI.QueryWidget(Id(:auth_none), :Value))
      user_in = Builtins.tostring(UI.QueryWidget(Id(:user_in), :Value))
      pass_in = Builtins.tostring(UI.QueryWidget(Id(:pass_in), :Value))
      user_out = Builtins.tostring(UI.QueryWidget(Id(:user_out), :Value))
      pass_out = Builtins.tostring(UI.QueryWidget(Id(:pass_out), :Value))

      target = {
        "target"      => Ops.get(IscsiClientLib.currentRecord, 1, ""),
        "portal"      => Ops.get(IscsiClientLib.currentRecord, 0, ""),
        "iface"       => Ops.get(IscsiClientLib.currentRecord, 2, "default"),
        "authmethod"  => auth_none ? "None" : "CHAP",
        "username"    => user_out,
        "password"    => pass_out,
        "username_in" => user_in,
        "password_in" => pass_in
      }
      if IscsiClientLib.connected(true) ||
          IscsiClientLib.loginIntoTarget(target)
        #		IscsiClientLib::currentRecord = [target["portal"]:"", target["target"]:"", target["iface"]:"default"];
        IscsiClientLib.setStartupStatus(
          Convert.to_string(UI.QueryWidget(Id("startup"), :Value))
        )
        IscsiClientLib.readSessions
        return true
      else
        return false
      end
    end
  end
end
