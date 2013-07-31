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
          "List of current sessions. To add a new target, select it and press <b>Add</b>.\n" +
            "To remove it, press <b>Log Out</b>.\n" +
            "To change the start-up status, press <b>Toggle</b>.\n"
        ) +
          # Warning
          _("<h1>Warning</h1>") +
          _(
            "<p>When accessing an iSCSI device <b>READ</b>/<b>WRITE</b>, make sure that this access is exclusive. Otherwise there is a potential risk of data corruption.</p>\n"
          ),
        "initiator_name" => _(
          "<p><b>InitiatorName</b> is a value from <tt>/etc/iscsi/initiatorname.iscsi</tt>. \nIn case you have iBFT, this value will be added from there and you are only able to change it in the BIOS setup.</p>"
        ),
        "isns"           => _(
          "If you want to use <b>iSNS</b> (Internet  Storage  Name Service) for discovering targets instead of the default SendTargets method,\nfill in the IP address of the iSNS server and port. The default port should be 3205.\n"
        ),
        # discovery new target
        "discovery"      => _("<h1>iSCSI Initiator</h1>") +
          _(
            "Enter the <b>IP Address</b> of the discovered server.\n" +
              "Only change <b>Port</b> if needed. For authentication, use <b>Username</b> and <b>Password</b>. If you do not need authentication,\n" +
              "select <b>No Authentication</b>.\n"
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
          _(
            "Select the type of authentication and enter the <b>Username</b> and <b>Password</b>."
          ) +
          _("<h1>Startup</h1>") +
          _(
            "<p><b>manual</b> is for iSCSI targets which are not to be connected by\n" +
              "default, the user needs to connect them manually</p>\n" +
              "<p><b>onboot</b> is for iSCSI targets to be connected during boot, i.e. when\n" +
              "root is on iSCSI. As such it will be evaluated by the initrd.</p>\n" +
              "<p><b>automatic</b> is for iSCSI targets to be connected when the iSCSI service\n" +
              "starts up.</p>\n"
          ),
        # list of discovered targets
        "discovered"     => _(
          "List of discovered targets. Start a new <b>Discovery</b> or <b>Connect</b> to any target."
        ),
        "ibft_table"     => _("<h1>iBTF</h1>") +
          "The <p>iSCSI Boot Firmware Table</p> is a table created by the iSCSI boot firmware in order to\npass parameters about the iSCSI boot device to the loaded OS."
      } 

      # EOF
    end
  end
end
