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
  module IscsiClientDialogsInclude
    def initialize_iscsi_client_dialogs(include_target)
      textdomain "iscsi-client"

      Yast.import "Label"
      Yast.import "Wizard"
      Yast.import "IscsiClient"
      Yast.import "CWMServiceStart"
      Yast.import "CWMTab"
      Yast.import "CWM"
      Yast.import "Stage"
      Yast.import "Mode"

      @current_tab = "general"

      Yast.include include_target, "iscsi-client/helps.rb"
      Yast.include include_target, "iscsi-client/widgets.rb"

      @widgets = {
        "auto_start_up"    => CWMServiceStart.CreateAutoStartWidget(
          {
            "get_service_auto_start" => fun_ref(
              IscsiClientLib.method(:GetStartService),
              "boolean ()"
            ),
            "set_service_auto_start" => fun_ref(
              IscsiClientLib.method(:SetStartService),
              "void (boolean)"
            ),
            # radio button (starting SLP service - option 1)
            "start_auto_button"      => _(
              "When &Booting"
            ),
            # radio button (starting SLP service - option 2)
            "start_manual_button"    => _(
              "&Manually"
            ),
            "help"                   => Builtins.sformat(
              CWMServiceStart.AutoStartHelpTemplate,
              # part of help text, used to describe radiobuttons (matching starting SLP service but without "&")
              _("When Booting"),
              # part of help text, used to describe radiobuttons (matching starting SLP service but without "&")
              _("Manually")
            )
          }
        ),
        "isns"             => {
          "widget"            => :custom,
          "custom_widget"     => HBox(
            MinWidth(
              16,
              HBox(
                TextEntry(Id(:isns_address), _("iSNS Address")),
                TextEntry(Id(:isns_port), _("iSNS Port"))
              )
            )
          ),
          "init"              => fun_ref(method(:initISNS), "void (string)"),
          "validate_type"     => :function,
          "validate_function" => fun_ref(
            method(:validateISNS),
            "boolean (string, map)"
          ),
          "store"             => fun_ref(
            method(:storeISNS),
            "symbol (string, map)"
          ),
          "help"              => Ops.get_string(@HELPS, "isns", "")
        },
        "initiator_name"   => {
          "widget"            => :custom,
          "custom_widget"     => HBox(
            MinWidth(
              16,
              HBox(
                # name of iscsi client (/etc/iscsi/initiatorname.iscsi)
                TextEntry(Id(:initiator_name), _("&Initiator Name")),
                MinWidth(
                  8,
                  ComboBox(
                    Id(:offload_card),
                    Opt(:notify),
                    # prefer to not translate 'Offload' unless there is a well
                    # known word for this technology (it's special hardware
                    # shifting load from processor to card)
                    _("Offload Car&d"),
                    []
                  )
                )
              )
            )
          ),
          "init"              => fun_ref(method(:initInitName), "void (string)"),
          "validate_type"     => :function,
          "validate_function" => fun_ref(
            method(:validateInitName),
            "boolean (string, map)"
          ),
          "store"             => fun_ref(
            method(:storeInitName),
            "symbol (string, map)"
          ),
          "handle"            => fun_ref(
            method(:handleOffload),
            "symbol (string, map)"
          ),
          "help"              => Ops.get_string(@HELPS, "initiator_name", "")
        },
        # table of connected targets
        "connected_table"  => {
          "widget"        => :custom,
          "custom_widget" => VBox(
            Table(
              Id(:connected),
              Opt(:notify, :immediate),
              Header(
                _("Interface"),
                _("Portal Address"),
                _("Target Name"),
                _("Start-Up")
              ),
              []
            ),
            Left(
              HBox(
                PushButton(Id(:add), _("Add")),
                PushButton(Id(:edit), _("Edit")),
                PushButton(Id(:del), _("Disconnect"))
              )
            )
          ),
          "init"          => fun_ref(
            method(:initConnectedTable),
            "void (string)"
          ),
          "handle"        => fun_ref(
            method(:handleConnectedTable),
            "symbol (string, map)"
          ),
          "help"          => Ops.get_string(@HELPS, "server_table", "")
        },
        # table of discovered targets
        "discovered_table" => {
          "widget"        => :custom,
          "custom_widget" => VBox(
            Table(
              Id(:discovered),
              Opt(:notify, :immediate),
              Header(
                _("Interface"),
                _("Portal Address"),
                _("Target Name"),
                _("Connected")
              ),
              []
            ),
            Left(
              HBox(
                PushButton(Id(:discovery), _("Discovery")),
                PushButton(Id(:connect), _("Connect")),
                PushButton(Id(:delete), Label.DeleteButton)
              )
            )
          ),
          "help"          => Ops.get_string(@HELPS, "discovered", ""),
          "init"          => fun_ref(
            method(:initDiscoveredTable),
            "void (string)"
          ),
          "handle"        => fun_ref(
            method(:handleDiscoveredTable),
            "symbol (string, map)"
          )
        },
        # dialog for all targets from portal (connected/disconnected)
        "targets_table"    => {
          "widget"        => :custom,
          "custom_widget" => VBox(
            Table(
              Id(:targets),
              Opt(:notify, :immediate),
              Header(
                _("Interface"),
                _("Portal Address"),
                _("Target Name"),
                _("Start-Up")
              ),
              []
            ),
            Left(HBox(PushButton(Id(:connect), _("Connect"))))
          ),
          "init"          => fun_ref(method(:initTargetTable), "void (string)"),
          "handle"        => fun_ref(
            method(:handleTargetTable),
            "symbol (string, map)"
          )
        },
        # authentification dialog for add/discovery target
        "discovery_auth"   => {
          "widget"        => :custom,
          "custom_widget" => VBox(
            CheckBoxFrame(
              Id(:auth_none),
              Opt(:invertAutoEnable),
              _("No Discovery Authentication"),
              true,
              VBox(
                Left(Label(_("Authentication by Initiator"))),
                HBox(
                  HWeight(2, TextEntry(Id(:user_in), _("Username"))),
                  HWeight(1, Password(Id(:pass_in), _("Password")))
                ),
                VSpacing(2),
                Left(Label(_("Authentication by Targets"))),
                HBox(
                  HWeight(2, TextEntry(Id(:user_out), _("Username"))),
                  HWeight(1, Password(Id(:pass_out), _("Password")))
                )
              )
            )
          ),
          "init"          => fun_ref(method(:initDiscAuth), "void (string)"),
          #		"handle" : handleDiscAuth,
          #		"validate_type" : `function,
          #		"validate_function" : validateDiscAuth,
          "help"          => Ops.get_string(
            @HELPS,
            "conn_auth",
            ""
          )
        },
        # authentication dialog for add target
        "conn_auth"        => {
          "widget"            => :custom,
          "custom_widget"     => VBox(
            CheckBoxFrame(
              Id(:auth_none),
              Opt(:invertAutoEnable),
              _("No Login Authentication"),
              true,
              VBox(
                Left(Label(_("Authentication by Initiator"))),
                HBox(
                  HWeight(2, TextEntry(Id(:user_in), _("Username"))),
                  HWeight(1, Password(Id(:pass_in), _("Password")))
                ),
                VSpacing(2),
                Left(Label(_("Authentication by Targets"))),
                HBox(
                  HWeight(2, TextEntry(Id(:user_out), _("Username"))),
                  HWeight(1, Password(Id(:pass_out), _("Password")))
                )
              )
            )
          ),
          "init"              => fun_ref(method(:initConnAuth), "void (string)"),
          #		"handle" : handleDiscAuth,
          "validate_type"     => :function,
          "validate_function" => fun_ref(
            method(:validateConnAuth),
            "boolean (string, map)"
          ),
          "help"              => Ops.get_string(@HELPS, "conn_auth", "")
        },
        "startup"          => {
          "widget" => :combobox,
          "opt"    => [:hstretch, :notify],
          "label"  => _("Startup"),
          "items"  => [
            # iSCSI target has to be connected manually
            ["manual", _("manual")],
            # iSCSI target available at boot (respected by 'dracut')
            ["onboot", _("onboot")],
            # iSCSI target enabled automatically (by 'systemd')
            ["automatic", _("automatic")]
          ]
        },
        # widget for portal address
        "server_location"  => {
          "widget"            => :custom,
          "custom_widget"     => HBox(
            TextEntry(Id(:hostname), _("IP Address")),
            IntField(Id(:port), _("Port"), 0, 65535, 3260)
          ),
          "init"              => fun_ref(
            method(:initServerLocation),
            "void (string)"
          ),
          "validate_type"     => :function,
          "validate_function" => fun_ref(
            method(:validateServerLocation),
            "boolean (string, map)"
          )
        },
        "ibft_table"       => {
          "widget"        => :custom,
          "custom_widget" => VBox(
            Table(Id(:bios), Header(_("Key"), _("Value")), [])
          ),
          "init"          => fun_ref(method(:initiBFT), "void (string)"),
          "help"          => Ops.get_string(@HELPS, "ibft_table", "")
        }
      }


      @tabs_descr = {
        # service status dialog
        "general"    => {
          "header"       => _("Service"),
          "contents"     => VBox(
            VStretch(),
            HBox(
              HStretch(),
              HSpacing(1),
              VBox(
                "auto_start_up",
                VSpacing(2),
                "initiator_name",
                VSpacing(2),
                "isns",
                VSpacing(2)
              ),
              HSpacing(1),
              HStretch()
            ),
            VStretch()
          ),
          "widget_names" => ["auto_start_up", "initiator_name", "isns"]
        },
        # list og connected targets
        "client"     => {
          "header"       => _("Connected Targets"),
          "contents"     => VBox(
            HBox(HSpacing(1), VBox("connected_table"), HSpacing(1))
          ),
          "widget_names" => ["connected_table"]
        },
        # list of discovered targets
        "discovered" => {
          "header"       => _("Discovered Targets"),
          "contents"     => VBox(HBox(VBox("discovered_table"))),
          "widget_names" => ["discovered_table"]
        },
        "ibft"       => {
          "header"       => "iBFT",
          "contents"     => VBox(
            HBox(HSpacing(1), VBox("ibft_table"), HSpacing(1))
          ),
          "widget_names" => ["ibft_table"]
        }
      }
    end

    # main tabbed dialog
    def GlobalDialog
      if Stage.initial
        Ops.set(@tabs_descr, ["general", "widget_names"], ["initiator_name"])
      end
      caption = _("iSCSI Initiator Overview")

      tab_order = ["general", "client"]
      tab_order = Builtins.add(tab_order, "discovered") if !Stage.initial
      if Ops.greater_than(Builtins.size(IscsiClientLib.getiBFT), 0)
        tab_order = Builtins.add(tab_order, "ibft")
      end

      widget_descr = {
        "tab" => CWMTab.CreateWidget(
          {
            "tab_order"    => tab_order,
            "tabs"         => @tabs_descr,
            "widget_descr" => @widgets,
            "initial_tab"  => Stage.initial ? "general" : @current_tab,
            "tab_help"     => _("<h1>iSCSI Initiator</h1>")
          }
        )
      }
      contents = VBox("tab")
      w = CWM.CreateWidgets(
        ["tab"],
        Convert.convert(
          widget_descr,
          :from => "map",
          :to   => "map <string, map <string, any>>"
        )
      )
      help = CWM.MergeHelps(w)
      contents = CWM.PrepareDialog(contents, w)
      Wizard.SetContentsButtons(
        caption,
        contents,
        help,
        Label.BackButton,
        Mode.installation ? Label.NextButton : Label.FinishButton
      )
      Wizard.SetNextButton(:next, Label.OKButton)
      Wizard.SetAbortButton(:abort, Label.CancelButton)
      Wizard.HideBackButton
      ret = CWM.Run(
        w,
        { :abort => fun_ref(method(:ReallyAbort), "boolean ()") }
      )
      ret
    end

    # authentication dialog for add new target
    def DiscAuthDialog(return_to)
      @current_tab = return_to
      caption = _("iSCSI Initiator Discovery") # bug #148963 _("iSCSI Target Login");
      w = CWM.CreateWidgets(["server_location", "discovery_auth"], @widgets)
      contents = VBox(
        VStretch(),
        HBox(
          HStretch(),
          HSpacing(1),
          VBox(
            Ops.get_term(w, [0, "widget"]) { VSpacing(1) },
            VSpacing(2),
            Ops.get_term(w, [1, "widget"]) { VSpacing(1) },
            VSpacing(2)
          ),
          HSpacing(1),
          HStretch()
        ),
        VStretch()
      )

      help = CWM.MergeHelps(w)
      contents = CWM.PrepareDialog(contents, w)
      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.get_string(@HELPS, "discovery", ""),
        Label.BackButton,
        Label.NextButton
      )

      ret = CWM.Run(
        w,
        { :abort => fun_ref(method(:ReallyAbort), "boolean ()") }
      )
      deep_copy(ret)
    end

    # list of connected targets
    def TargetsDialog
      @current_tab = "client"
      caption = _("iSCSI Initiator Discovery")
      w = CWM.CreateWidgets(["targets_table"], @widgets)
      contents = VBox(
        HBox(HSpacing(1), VBox(Ops.get_term(w, [0, "widget"]) { VSpacing(1) }), HSpacing(
          1
        ))
      )
      help = CWM.MergeHelps(w)
      contents = CWM.PrepareDialog(contents, w)
      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.get_string(@HELPS, "targets_table", ""),
        Label.BackButton,
        Label.NextButton
      )
      ret = CWM.Run(
        w,
        { :abort => fun_ref(method(:ReallyAbort), "boolean ()") }
      )
      deep_copy(ret)
    end

    # authentication for connect to portal
    def ConnAuthDialog(return_to)
      @current_tab = return_to
      caption = _("iSCSI Initiator Discovery")
      w = CWM.CreateWidgets(["startup", "conn_auth"], @widgets)

      contents = VBox(
        VStretch(),
        HBox(
          HStretch(),
          HSpacing(1),
          VBox(
            Ops.get_term(w, [0, "widget"]) { VSpacing(1) },
            Ops.get_term(w, [1, "widget"]) { VSpacing(1) },
            VSpacing(2)
          ),
          HSpacing(1),
          HStretch()
        ),
        VStretch()
      )

      help = CWM.MergeHelps(w)
      contents = CWM.PrepareDialog(contents, w)
      Wizard.SetContentsButtons(
        caption,
        contents,
        Ops.get_string(@HELPS, "conn_auth", ""),
        Label.BackButton,
        Label.NextButton
      )

      if (IscsiClientLib.iBFT?(IscsiClientLib.getCurrentNodeValues))
        UI.ChangeWidget(Id("startup"), :Enabled, false)
      end

      ret = CWM.Run(
        w,
        { :abort => fun_ref(method(:ReallyAbort), "boolean ()") }
      )
      deep_copy(ret)
    end
  end
end
