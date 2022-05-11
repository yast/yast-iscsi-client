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
# File:
#  iscsi-client_finish.ycp
#
# Module:
#  Step of base installation finish
#
# Authors:
#  Michal Zugec <mzugec@suse.cz>
#
require "yast2/systemd/socket"

require "shellwords"

module Yast
  class IscsiClientFinishClient < Client
    def main
      Yast.import "UI"

      textdomain "iscsi-client"

      Yast.import "Directory"
      Yast.import "String"
      Yast.import "IscsiClientLib"
      Yast.import "Service"
      Yast.include self, "installation/misc.rb"

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

      Builtins.y2milestone("starting scsi-client_finish")
      Builtins.y2debug("func=%1", @func)
      Builtins.y2debug("param=%1", @param)

      if @func == "Info"
        return {
          "steps" => 1,
          # progress step title
          "title" => _("Saving iSCSI configuration..."),
          "when"  => [:installation, :update, :autoinst]
        }
      elsif @func == "Write"
        # write open-iscsi database of automatic connected targets
        WFM.Execute(
          path(".local.bash"),
          "test -d /etc/iscsi/ && " \
            "mkdir -p #{Installation.destdir.shellescape}/etc/iscsi && " \
            "cp -a /etc/iscsi/* #{Installation.destdir.shellescape}/etc/iscsi/"
        )
        if Ops.greater_than(Builtins.size(IscsiClientLib.sessions), 0)
          Builtins.y2milestone("enabling iscsi and iscsid service/socket")
          socket = Yast2::Systemd::Socket.find("iscsid")
          socket.enable if socket
          # enable iscsi and iscsid service
          Service.Enable("iscsid")
          Service.Enable("iscsi")
          enable_iscsiuio
        end
      else
        Builtins.y2error("unknown function: %1", @func)
        @ret = nil
      end

      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("iscsi-client_finish finished")
      deep_copy(@ret)
    end

  private

    # Enables the iscsiuio service if needed
    def enable_iscsiuio
      if !IscsiClientLib.iscsiuio_relevant?
        Builtins.y2milestone("iscsiuio is not needed")
        return
      end

      Builtins.y2milestone("enabling iscsiuio socket and service")
      socket = Yast2::Systemd::Socket.find("iscsiuio")
      if socket
        socket.enable
      else
        Service.Enable("iscsiuio")
      end
    end
  end
end

Yast::IscsiClientFinishClient.new.main
