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
# File:	include/iscsi-client/wizards.ycp
# Package:	Configuration of iscsi-client
# Summary:	Wizards definitions
# Authors:	Michal Zugec <mzugec@suse.cz>
#
# $Id$
module Yast
  module IscsiClientWizardsInclude
    def initialize_iscsi_client_wizards(include_target)
      Yast.import "UI"

      textdomain "iscsi-client"

      Yast.import "Sequencer"
      Yast.import "Wizard"

      Yast.include include_target, "iscsi-client/complex.rb"
      Yast.include include_target, "iscsi-client/dialogs.rb"
    end

    # Main workflow of the iscsi-client configuration
    # @return sequence result
    def MainSequence
      # FIXME: adapt to your needs
      aliases = {
        "global"    => lambda { GlobalDialog() },
        "disc_auth" => lambda { DiscAuthDialog("client") },
        "targets"   => lambda { TargetsDialog() },
        "conn_auth" => lambda { ConnAuthDialog("client") },
        "conn_disc" => lambda { ConnAuthDialog("discovered") },
        "edit_conn" => lambda { ConnAuthDialog("client") },
        "disc"      => lambda { DiscAuthDialog("discovered") }
      }

      # FIXME: adapt to your needs
      sequence = {
        "ws_start"  => "global",
        "global"    => {
          :abort => :abort,
          :next  => :next,
          :add   => "disc_auth",
          :edit  => "edit_conn",
          :conn  => "conn_disc",
          :disc  => "disc"
        },
        "disc_auth" => { :abort => :abort, :back => :back, :next => "targets" },
        "conn_disc" => { :abort => :abort, :back => :back, :next => "global" },
        "targets"   => {
          :abort     => :abort,
          :back      => :back,
          :next      => "global",
          :conn_auth => "conn_auth"
        },
        "conn_auth" => { :abort => :abort, :next => "targets" },
        "edit_conn" => { :abort => :abort, :next => "global" },
        "disc"      => { :abort => :abort, :back => :back, :next => "global" }
      }

      Wizard.OpenNextBackDialog
      Wizard.SetDesktopTitleAndIcon("iscsi-client") if Mode.normal

      ret = Sequencer.Run(aliases, sequence)

      Wizard.CloseDialog
      deep_copy(ret)
    end

    # Whole configuration of iscsi-client
    # @return sequence result
    def IscsiClientSequence
      aliases = {
        "read"  => [lambda { ReadDialog() }, true],
        "main"  => lambda { MainSequence() },
        "write" => [lambda { WriteDialog() }, true]
      }

      sequence = {
        "ws_start" => "read",
        "read"     => { :abort => :abort, :next => "main" },
        "main"     => { :abort => :abort, :next => "write" },
        "write"    => { :abort => :abort, :next => :next }
      }

      Wizard.OpenCancelOKDialog
      Wizard.SetDesktopTitleAndIcon("iscsi-client") if Mode.normal

      ret = Sequencer.Run(aliases, sequence)

      Wizard.CloseDialog
      deep_copy(ret)
    end

    # Whole configuration of iscsi-client but without reading and writing.
    # For use with autoinstallation.
    # @return sequence result
    def IscsiClientAutoSequence
      # Initialization dialog caption
      caption = _("iSCSI Initiator Configuration")
      # Initialization dialog contents
      contents = Label(_("Initializing..."))

      Wizard.CreateDialog
      Wizard.SetContentsButtons(
        caption,
        contents,
        "",
        Label.BackButton,
        Label.NextButton
      )

      ret = MainSequence()

      UI.CloseDialog
      deep_copy(ret)
    end
  end
end
