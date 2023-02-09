# |***************************************************************************
# |
# | Copyright (c) [2023] SUSE LLC
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
# | along with this program; if not, contact SUSE LLC
# |
# | To contact Novell about this file by physical or electronic mail,
# | you may find current contact information at www.suse.com
# |
# |***************************************************************************

require "yast"
require "installation/finish_client"
require "yast2/systemd/socket"
require "yast2/execute"

Yast.import "IscsiClientLib"
Yast.import "Installation"
Yast.import "Service"

module Y2IscsiClient
  # Finish client implementing the operations needed to transfer the iSCSI configuration to the
  # target system at the end of installation
  class FinishClient < ::Installation::FinishClient
    include Yast::I18n

    def initialize
      super
      textdomain "iscsi-client"
    end

    def title
      _("Saving iSCSI configuration...")
    end

    def modes
      [:installation, :update, :autoinst]
    end

    def write
      copy_configuration
      enable
    end

  private

    # Copies open-iscsi configuration and databases to the target system
    def copy_configuration
      return unless File.directory?("/etc/iscsi")

      Yast::Execute.locally!(
        "mkdir", "-p", "#{Yast::Installation.destdir}/etc/iscsi", "&&",
        "cp", "-a", "/etc/iscsi/*", "#{Installation.destdir}/etc/iscsi/"
      )
    rescue Cheetah::ExecutionFailed
      log.error "Failed to copy the iSCSI configuration"
    end

    # Enables all needed open-iscsi sockets and services
    def enable
      return if Yast::IscsiClientLib.sessions.empty?

      log.info "Enabling iscsi and iscsid service/socket"
      socket = Yast2::Systemd::Socket.find("iscsid")
      socket&.enable

      # enable iscsi and iscsid service
      Yast::Service.Enable("iscsid")
      Yast::Service.Enable("iscsi")
      enable_iscsiuio
    end

    # Enables the iscsiuio service if needed
    def enable_iscsiuio
      if !Yast::IscsiClientLib.iscsiuio_relevant?
        log.info "iscsiuio is not needed"
        return
      end

      log.info "enabling iscsiuio socket or service"
      socket = Yast2::Systemd::Socket.find("iscsiuio")
      if socket
        socket.enable
      else
        Yast::Service.Enable("iscsiuio")
      end
    end
  end
end
