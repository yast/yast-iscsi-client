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
# File:	include/iscsi-client/helps.ycp
# Package:	Configuration of iscsi-client
# Summary:	Help texts of all the dialogs
# Authors:	Michal Zugec <mzugec@suse.cz>
#
# $Id$
module Yast
  module IscsiClientHelpsInclude
    def initialize_iscsi_client_helps(include_target)
      textdomain "iscsi-client"

      use_bidirectional_auth = "If authentication is needed for secure access, please use <b>Authentication by Initiator</b> and <b>Authentication by Targets</b> " \
      "together. Please do not only use one of them for security reasons.\n"
      # All helps are here
      @HELPS = {
        # Read dialog help 1/2
        "read"           => _(
          "<p><b><big>Initializing iSCSI Initiator Configuration</big></b><br>\nPlease wait...<br></p>\n"
        ) +
          # Read dialog help 2/2
          _(
            "<p><b><big>Aborting Initialization</big></b><br>\nSafely abort the configuration utility by pressing <b>Abort</b> now.</p>\n"
          ),
        # Write dialog help 1/2
        "write"          => _(
          "<p><b><big>Saving iSCSI Initiator Configuration</big></b><br>\nPlease wait...<br></p>\n"
        ) +
          # Write dialog help 2/2
          _(
            "<p><b><big>Aborting Saving</big></b><br>\n" +
              "Abort the save procedure by pressing <b>Abort</b>.\n" +
              "An additional dialog informs whether it is safe to do so.\n" +
              "</p>\n"
          ),
        # Summary dialog help 1/3
        "summary"        => _(
          "<p><b><big>iSCSI Initiator Configuration</big></b><br>\nConfigure an iSCSI initiator here.<br></p>\n"
        ) +
          # Summary dialog help 2/3
          _(
            "<p><b><big>Adding an iSCSI Initiator</big></b><br>\n" +
              "Select an iSCSI initiator from the list of detected initiators.\n" +
              "If your iSCSI initiator was not detected, use <b>Other (not detected)</b>.\n" +
              "Then press <b>Configure</b>.</p>\n"
          ) +
          # Summary dialog help 3/3
          _(
            "<p><b><big>Editing or Deleting</big></b><br>\n" +
              "If you press <b>Edit</b>, an additional dialog in which to change\n" +
              "the configuration opens.</p>\n"
          ),
        # Ovreview dialog help 1/3
        "overview"       => _(
          "<p><b><big>iSCSI Initiator Configuration Overview</big></b><br>\n" +
            "Obtain an overview of installed iSCSI initiators. Additionally\n" +
            "edit their configurations.<br></p>\n"
        ) +
          # Ovreview dialog help 2/3
          _(
            "<p><b><big>Adding an iSCSI Initiator</big></b><br>\nPress <b>Add</b> to configure an iSCSI initiator.</p>\n"
          ) +
          # Ovreview dialog help 3/3
          _(
            "<p><b><big>Editing or Deleting</big></b><br>\n" +
              "Choose an iSCSI Initiator to change or remove.\n" +
              "Then press <b>Edit</b> or <b>Delete</b> as desired.</p>\n"
          ),
        # table of connected targets
        "server_table"   => _(
          "<p>List of current sessions.</p>" \
            "<p>Use the <b>Add</b> button to get additional targets. A discovery is started to " \
            "detect new targets and the start-up mode of already connected targets keeps " \
            "unchanged.<br>" \
            "Use <b>Disconnect</b> to cancel the connection and with it remove the target from the list.<br>" \
            "To change the start-up status, press <b>Edit</b>.</p>"
        ) +
          # Warning
          _("<h1>Warning</h1>") +
          _(
            "<p>When accessing an iSCSI device <b>READ</b>/<b>WRITE</b>, make sure that this access is exclusive. Otherwise there is a potential risk of data corruption.</p>\n"
          ),
        "initiator_name" => _(
          "<p><b>Initiator Name</b> is a value from <tt>/etc/iscsi/initiatorname.iscsi</tt>. \nIn case you have iBFT, this value will be added from there and you are only able to change it in the BIOS setup.</p>"
        ),
        "isns"           => _(
          "If you want to use <b>iSNS</b> (Internet  Storage  Name Service) for discovering targets instead of the default SendTargets method,\nfill in the IP address of the iSNS server and port. The default port should be 3205.\n"
        ),
        # discovery new target
        "discovery"      => _("<h1>iSCSI Initiator</h1>") +
          _(
            "Enter the <b>IP Address</b> of the iSCSI target server.\n" +
              "Only change <b>Port</b>. If you do not need authentication,\n" +
              "select <b>No Discovery Authentication</b>. " +
               use_bidirectional_auth
          ) +
          # Warning
          _("<h1>Warning</h1>") +
          _(
            "<p>When accessing an iSCSI device <b>READ</b>/<b>WRITE</b>, make sure that this access is exclusive. Otherwise there is a potential risk of data corruption.</p>\n"
          ),
        # dialog for all targets from portal (connected/disconnected)
        "targets_table"  => _(
          "<h1>iSCSI Initiator</h1>"
        ) +
          _(
            "List of nodes offered by the iSCSI target. Select one item and click <b>Connect</b>.  "
          ),
        # authentification dialog for add/discovery target
        "conn_auth"      => _(
          "<h1>iSCSI Initiator</h1>"
        ) +
          _("<h1>Startup</h1>") +
          _(
            "<p><b>manual</b> is for iSCSI targets which are not to be connected by\n" +
              "default, the user needs to connect them manually</p>\n" +
              "<p><b>onboot</b> is for iSCSI targets to be connected during boot, i.e. when\n" +
              "root is on iSCSI. As such it will be evaluated by the initrd.</p>\n" +
              "<p><b>automatic</b> is for iSCSI targets to be connected when the iSCSI service\n" +
              "starts up.</p>\n"
          ) +
        _("<h1>Authentication</h1>") +
        _(
          "<p>The default setting here is <i>No Authentication</i>. Uncheck the checkbox if " \
          "authentication is needed for security reasons." \
          + use_bidirectional_auth + "</p>"
          ),
        # list of discovered targets
        "discovered"     => _(
          "<p>This screen shows the list of discovered targets.</p>" \
          "<p>Use the <b>Discovery</b> button to get available iSCSI targets " \
          "from a server specified by IP address.<br>" \
          "<b>Connect</b> to a target to establih the connection. If login was successful " \
          "the column <i>Connected</i> shows status 'True' and the target will appear on " \
          "the <i>Connected Targets</i> screen.<br>" \
          "To remove a target use the <b>Delete</b> button.<br> <b>Hint:</b> " \
          "Removing of targets is only possible for not connected onces. " \
          "If required, <b>Disconnect</b> at <i>Connected Targets</i> first.</p>" \
          "<p><b>Please note:</b> Starting the <b>Discovery</b> again means doing a re-discovery " \
          "of targets which possibly will change the start-up mode of already connected targets " \
          "(to default 'manual'). " \
          "Switch to <i>Connected Targets</i> screen and use the <b>Add</b> button if you want " \
          "to add new targets without changing the start-up mode.</p>"
        ),
        "ibft_table"     => _("<h1>iBTF</h1>") +
          "The <p>iSCSI Boot Firmware Table</p> is a table created by the iSCSI boot firmware in order to\npass parameters about the iSCSI boot device to the loaded OS."
      } 

      # EOF
    end
  end
end
