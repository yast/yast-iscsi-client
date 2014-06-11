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
  class InstIscsiClientClient < Client
    def main
      Yast.import "UI"

      #**
      # <h3>Configuration of iscsi-client</h3>

      textdomain "iscsi-client"

      # The main ()
      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("IscsiClient module started")

      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Summary"
      Yast.import "ModuleLoading"
      Yast.import "PackagesProposal"
      Yast.import "Installation"
      Yast.import "String"
      Yast.import "Mode"
      Yast.include self, "iscsi-client/wizards.rb"

      # main ui function
      @ret = nil

      Builtins.y2milestone("start iscsid")
      SCR.Execute(
        path(".target.bash"),
        "mkdir -p /etc/iscsi; touch /etc/iscsi/initiatorname.iscsi; ln -s /etc/iscsi/initiatorname.iscsi /etc/initiatorname.iscsi"
      )
      # check initiator name, create if not exists
      #WFM::Execute (.local.bash,"test -d /etc/iscsi/ && /bin/cp -a /etc/iscsi/* " + String::Quote(Installation::destdir) + "/etc/iscsi/");
      IscsiClientLib.checkInitiatorName


      IscsiClientLib.getiBFT
      Builtins.y2milestone("Loading module %1", "iscsi_tcp")
      ModuleLoading.Load("iscsi_tcp", "", "", "", false, true)
      IscsiClientLib.LoadOffloadModules

      # start iscsid daemon and service 'iscsiuio'
      IscsiClientLib.startIScsid
      # try auto login to target
      IscsiClientLib.autoLogOn

      # add package open-iscsi and iscsiuio to installed system
      iscsi_packages = ["open-iscsi", "iscsiuio"]
      Builtins.y2milestone("Additional packages to be installed: %1",
                            iscsi_packages)
      PackagesProposal.AddResolvables(
          "iscsi-client",
          :package,
          iscsi_packages
        )

      if Mode.autoinst
        Builtins.y2milestone("Autoinstallation - IscsiClient module finished")
        return :next
      end

      # run dialog
      @ret = MainSequence()
      Builtins.y2debug("MainSequence ret=%1", @ret)

      # Finish
      Builtins.y2milestone("IscsiClient module finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret) 

      # EOF
    end
  end
end

Yast::InstIscsiClientClient.new.main
