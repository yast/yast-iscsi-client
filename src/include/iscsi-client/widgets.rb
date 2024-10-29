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
# Main file for iscsi-client configuration. Uses all other files.

require "shellwords"
require "y2iscsi_client/authentication"

module Yast
  module IscsiClientWidgetsInclude
    def initialize_iscsi_client_widgets(_include_target)
      textdomain "iscsi-client"
      Yast.import "IP"
      Yast.import "Arch"
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
    def initConnectedTable(_key)
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
    def handleConnectedTable(_key, event)
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

    def initISNS(_key)
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

    def validateISNS(_key, event)
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

    def storeISNS(_key, event)
      event = deep_copy(event)
      address = Convert.to_string(UI.QueryWidget(:isns_address, :Value))
      port = Convert.to_string(UI.QueryWidget(:isns_port, :Value))

      IscsiClientLib.setISNSConfig(address, port)
      IscsiClientLib.oldConfig
      nil
    end

    def initInitName(_key)
      Builtins.y2milestone("initiatorname %1", IscsiClientLib.initiatorname)
      UI.ChangeWidget(:initiator_name, :Value, IscsiClientLib.initiatorname)
      UI.ChangeWidget(:iface, :Items, IscsiClientLib.iface_items)
      UI.ChangeWidget(:iface, :Value, IscsiClientLib.selected_iface)
      log.info "Selected Iface: #{IscsiClientLib.selected_iface}"
      unless IscsiClientLib.getiBFT["iSCSI_INITIATOR_NAME"].to_s.empty?
        UI.ChangeWidget(:initiator_name, :Enabled, false)
        # Not sure if there is such a widget called :write
        UI.ChangeWidget(:write, :Enabled, false)
      end

      nil
    end

    def validateInitName(_key, event)
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
      return true if IscsiClientLib.initiatorname == i_name

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
            "\n" \
            "The correct syntax is\n" \
            "iqn.yyyy-mm.reversed.domain.name[:identifier]\n" \
            "or eui.yyyy-mm.reversed.domain.name[:identifier]\n" \
            "\n" \
            "Example:\n" \
            "iqn.2007-04.cz.server:storage.disk.sdb\n" \
            "\n" \
            "Do you want to use the name?\n"
          ))
        return go_on
      else
        return true
      end
    end

    def iface_value
      UI.QueryWidget(:iface, :Value).to_s
    end

    def storeInitName(_key, event)
      event = deep_copy(event)
      if Convert.to_string(UI.QueryWidget(:initiator_name, :Value)) !=
          IscsiClientLib.initiatorname
        # write initiatorname
        IscsiClientLib.writeInitiatorName(
          Convert.to_string(UI.QueryWidget(:initiator_name, :Value))
        )
        # Isn't this redundant with the code at IscsiClientLib.writeInitiatorName?
        if Stage.initial
          IscsiClientLib.restart_iscsid_initial
        else
          Service.Restart("iscsid")
        end
        log.info "write initiatorname #{IscsientLib.initiatorname}"
      end
      IscsiClientLib.iface = iface_value if iface_value != IscsiClientLib.selected_iface
      nil
    end

    def handleIface(_key, event)
      if event["EventReason"].to_s == "ValueChanged" && event["ID"] == :iface
        if iface_value != IscsiClientLib.iface
          IscsiClientLib.iface = iface_value
          log.info "handleIface iface: #{IscsiClientLib.iface}"
        end
      end
      nil
    end

    # ***************** iBFT table **************************
    def initiBFT(_key)
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
    def initDiscAuth(_key)
      nil
    end

    def initConnAuth(_key)
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
    def handleDiscAuth(_key, event)
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
        # FIXME: status unused, so this method do nothing
      end
      nil
    end

    def validateDiscAuth(_key, event)
      event = deep_copy(event)
      checkAuthEntry
    end
    # *******************Server Location ***********************

    def initServerLocation(_key)
      isns_info = IscsiClientLib.useISNS
      Builtins.y2milestone("is iSNS %1", isns_info["use"])
      if isns_info["use"]
        UI.ChangeWidget(:hostname, :Enabled, false)
        UI.ChangeWidget(:port, :Enabled, false)
      end

      nil
    end

    # do discovery to selected portal
    def validateServerLocation(_key, _event)
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
            "LC_ALL=POSIX host #{ip.shellescape}")
          Builtins.y2milestone("Cmd: host %1, result: %2", ip, result)
          output = result["stdout"] || ""

          if result["exit"] != 0
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

      # Store the content of /etc/iscsi/iscsi.conf into memory
      IscsiClientLib.getConfig

      auth_none = Convert.to_boolean(UI.QueryWidget(Id(:auth_none), :Value))
      user_in = Builtins.tostring(UI.QueryWidget(Id(:user_in), :Value))
      pass_in = Builtins.tostring(UI.QueryWidget(Id(:pass_in), :Value))
      user_out = Builtins.tostring(UI.QueryWidget(Id(:user_out), :Value))
      pass_out = Builtins.tostring(UI.QueryWidget(Id(:pass_out), :Value))

      auth = Y2IscsiClient::Authentication.new
      if !auth_none
        if !user_in.empty? && !pass_in.empty?
          auth.username_in = user_in
          auth.password_in = pass_in
        end
        if !user_out.empty? && !pass_out.empty?
          auth.username = user_out
          auth.password = pass_out
        end
      end

      # Check @current_tab (dialogs.rb) here. If it's "client", i.e. the
      # 'Add' button at 'Connected Targets' is used, create discovery
      # command with option --new. The start-up mode for already connected
      # targets won't change then (fate #317874, bnc #886796).
      option_new = (@current_tab == "client")
      IscsiClientLib.discover(ip, port, auth, only_new: option_new)
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
    def initDiscoveredTable(_key)
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
    def handleDiscoveredTable(_key, event)
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
            IscsiClientLib.removeRecord
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

    # ******************* target table *************************

    # initialize dialog for all targets from portal (connected/disconnected)
    def initTargetTable(_key)
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
    def handleTargetTable(_key, event)
      event = deep_copy(event)
      # enable/disable connect button according target is or not already connected
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

    # ***************** connection autentication *******************

    # login to target with authentication
    def validateConnAuth(_key, event)
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

    # get the possible startup modes as item list, architecture dependent
    def startup_items
      # iSCSI target has to be connected manually
      values = [["manual", _("manual")]]
      # iSCSI target available at boot (respected by 'dracut')
      values << ["onboot", _("onboot")] if !Arch.s390
      # iSCSI target enabled automatically (by 'systemd')
      values << ["automatic", _("automatic")]
    end
  end
end
