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
# File:	clients/iscsi-client_auto.ycp
# Package:	Configuration of iscsi-client
# Summary:	Client for autoinstallation
# Authors:	Michal Zugec <mzugec@suse.cz>
#
# $Id$
#
# This is a client for autoinstallation. It takes its arguments,
# goes through the configuration and return the setting.
# Does not do any changes to the configuration.

# @param function to execute
# @param map/list of iscsi-client settings
# @return [Hash] edited settings, Summary or boolean on success depending on called function
# @example map mm = $[ "FAIL_DELAY" : "77" ];
# @example map ret = WFM::CallFunction ("iscsi-client_auto", [ "Summary", mm ]);
module Yast
  class IscsiClientAutoClient < Client
    def main
      Yast.import "UI"

      textdomain "iscsi-client"

      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("IscsiClient auto started")

      Yast.import "IscsiClient"
      Yast.import "ModuleLoading"
      Yast.include self, "iscsi-client/wizards.rb"

      @ret = nil
      @func = ""
      @param = {}

      # Check arguments
      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          Ops.is_string?(WFM.Args(0))
        @func = Convert.to_string(WFM.Args(0))
        if Ops.greater_than(Builtins.size(WFM.Args), 1) &&
            Ops.is_map?(WFM.Args(1))
          @param = Convert.to_map(WFM.Args(1))
        end
      end
      Builtins.y2debug("func=%1", @func)
      Builtins.y2debug("param=%1", @param)

      # Create a summary
      if @func == "Summary"
        @ret = Ops.get_string(IscsiClient.Summary, 0, "")
      # Reset configuration
      elsif @func == "Reset"
        IscsiClient.Import({})
        @ret = {}
      # Change configuration (run AutoSequence)
      elsif @func == "Change"
        @ret = IscsiClientAutoSequence()
      # Import configuration
      elsif @func == "Import"
        @ret = IscsiClient.Import(@param)
      # Return actual state
      elsif @func == "Export"
        @ret = IscsiClient.Export
      # Return needed packages
      elsif @func == "Packages"
        @ret = IscsiClient.AutoPackages
      elsif @func == "GetModified"
        @ret = IscsiClient.modified
      elsif @func == "SetModified"
        IscsiClient.modified = true
        IscsiClient.configured = true
      # Read current state
      elsif @func == "Read"
        Yast.import "Progress"
        @progress_orig = Progress.set(false)
        @ret = IscsiClient.Read
        Progress.set(@progress_orig)
      # Write given settings
      elsif @func == "Write"
        Yast.import "Progress"
        @progress_orig = Progress.set(false)
        IscsiClient.write_only = true
        ModuleLoading.Load("iscsi_tcp", "", "", "", false, true)
        IscsiClientLib.autoyastPrepare
        IscsiClientLib.start_services_initial
        @ret = IscsiClient.Write
        Progress.set(@progress_orig)
      else
        Builtins.y2error("Unknown function: %1", @func)
        @ret = false
      end

      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("IscsiClient auto finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret)

      # EOF
    end
  end
end

Yast::IscsiClientAutoClient.new.main
