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
# File:	include/iscsi-client/complex.ycp
# Package:	Configuration of iscsi-client
# Summary:	Dialogs definitions
# Authors:	Michal Zugec <mzugec@suse.cz>
#
# $Id$
module Yast
  module IscsiClientComplexInclude
    def initialize_iscsi_client_complex(include_target)
      Yast.import "UI"

      textdomain "iscsi-client"

      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "Wizard"
      Yast.import "IscsiClient"
      Yast.import "IscsiClientLib"

      Yast.include include_target, "iscsi-client/helps.rb"
    end

    # Return a modification status
    # @return true if data was modified
    def Modified
      IscsiClient.Modified
    end

    def ReallyAbort
      !IscsiClient.Modified || Popup.ReallyAbort(true)
    end

    def PollAbort
      UI.PollInput == :abort
    end

    # Read settings dialog
    # @return `abort if aborted and `next otherwise
    def ReadDialog
      Wizard.RestoreHelp(Ops.get_string(@HELPS, "read", ""))
      # IscsiClient::AbortFunction = PollAbort;
      ret = IscsiClient.Read
      ret ? :next : :abort
    end

    # Write settings dialog
    #
    # @return [Symbol] :abort if aborted, :next otherwise
    def WriteDialog
      help = @HELPS.fetch("write") { "" }

      Wizard.CreateDialog
      Wizard.RestoreHelp(help)
      result = IscsiClient.Write
      Wizard.CloseDialog

      return :next if result
      :abort
    end
  end
end
