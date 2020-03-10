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
# File:	modules/IscsiClient.ycp
# Package:	Configuration of iscsi-client
# Summary:	IscsiClient settings, input and output functions
# Authors:	Michal Zugec <mzugec@suse.cz>
#
# $Id$
#
# Representation of the configuration of iscsi-client.
# Input and output routines.

require "yast"
require "yast2/system_service"
require "yast2/compound_service"

module Yast
  class IscsiClientClass < Module
    def main
      textdomain "iscsi-client"

      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Summary"
      Yast.import "Message"
      Yast.import "Service"
      Yast.import "Package"
      Yast.import "Packages"
      Yast.import "Popup"
      Yast.import "Mode"
      Yast.import "Confirm"
      Yast.import "Label"
      Yast.import "NetworkService"
      Yast.import "IscsiClientLib"
      Yast.import "Stage"

      @configured = false

      # Data was modified?
      @modified = false

      @proposal_valid = false

      # FIXME: write_only seems to be not in use
      # Write only, used during autoinstallation.
      # Don't run services and SuSEconfig, it's all done at one place.
      @write_only = false

      # Abort function
      # return boolean return true if abort
      @AbortFunction = fun_ref(method(:Modified), "boolean ()")
    end

    # Returns iSCSI related services
    #
    # @return [Yast2::CompundService]
    def services
      # TODO: Having a combination of services and sockets in a compoud service
      #   do not smell very well and the user might be very carefull on the
      #   'after reboot' selection having to choose correctly for enabling the
      #   desired option (bsc#1160606).
      @services ||= Yast2::CompoundService.new(
        Yast2::SystemService.find("iscsid"),
        Yast2::SystemService.find("iscsiuio"),
        # It seems that moving it to the end help when iscsid socket is active
        # and need to be restarted. (bsc#853300, bsc#1160606)
        Yast2::SystemService.find("iscsi")
      )
    end

    # Abort function
    # @return [Boolean] return true if abort
    def Abort
      return @AbortFunction.call == true if @AbortFunction != nil
      false
    end

    # Data was modified?
    # @return true if modified
    def Modified
      Builtins.y2debug("modified=%1", @modified)
      @modified
    end

    # check if package open-iscsi is installed
    def installed_packages
      # don't check interactively for packages (bnc#367300)
      # skip it during second stage or when create AY profile
      return true if Stage.cont || Stage.initial || Mode.config
      Builtins.y2milestone("Check if open-iscsi package installed")
      ret = false
      if !Package.InstallMsg(
        "open-iscsi",
        _(
          "<p>To configure the iSCSI initiator, the <b>%1</b> package must be installed.</p>"
        ) +
          _("<p>Install it now?</p>")
      )
        Popup.Error(Message.CannotContinueWithoutPackagesInstalled)
      else
        ret = true
      end
      ret
    end

    # Dump the iscsi-client settings to a single map
    # (For use by autoinstallation.)
    # @return [Hash] Dumped settings (later acceptable by Import ())
    def Export
      tgets = []
      Builtins.foreach(IscsiClientLib.sessions) do |sess|
        sl = Builtins.splitstring(sess, " ")
        target = Ops.get(sl, 1, "")
        portal = Ops.get(sl, 0, "")
        iface = Ops.get(sl, 2, "default")
        IscsiClientLib.currentRecord = [portal, target, iface]
        auth = IscsiClientLib.getNode
        new_target = {
          "target"  => target,
          "portal"  => portal,
          "iface"   => iface,
          "startup" => IscsiClientLib.getStartupStatus
        }
        if Ops.get_string(auth, "authmethod", "None") == "None"
          Ops.set(new_target, "authmethod", "None")
        else
          new_target = Builtins.union(new_target, auth)
        end
        tgets = Builtins.add(tgets, new_target)
      end
      IscsiClientLib.ay_settings = {}
      if !Builtins.isempty(tgets)
        IscsiClientLib.ay_settings = {
          "version"       => "1.0",
          "initiatorname" => IscsiClientLib.initiatorname,
          "targets"       => tgets
        }
        @configured = true
        @modified = true
      end
      deep_copy(IscsiClientLib.ay_settings)
    end

    # Read all iscsi-client settings
    # @return true on success
    def Read
      # IscsiClient read dialog caption
      caption = _("Initializing iSCSI Initiator Configuration")

      # TODO: FIXME Set the right number of stages
      steps = 4

      sl = 500
      Builtins.sleep(sl)

      # TODO: FIXME Names of real stages
      # We do not set help text here, because it was set outside
      Progress.New(
        caption,
        " ",
        steps,
        [
          # Progress stage 1/3
          _("Read the database"),
          # Progress stage 2/3
          _("Read the previous settings"),
          # Progress stage 3/3
          _("Detect the devices")
        ],
        [
          # Progress step 1/3
          _("Reading the database..."),
          # Progress step 2/3
          _("Reading the previous settings..."),
          # Progress step 3/3
          _("Detecting the devices..."),
          # Progress finished
          _("Finished")
        ],
        ""
      )

      # check if user is root - must be root
      return false if !Confirm.MustBeRoot
      return false if !NetworkService.RunningNetworkPopup
      Progress.NextStage
      return false if false
      Builtins.sleep(sl)

      # check if required package is installed
      return false if !installed_packages
      return false if IscsiClientLib.getiBFT == nil
      # Progress finished
      Progress.NextStage
      Builtins.sleep(sl)

      Progress.NextStage
      # check initiatorname - create it if no exists
      Builtins.y2milestone("Check initiator name")
      return false if !IscsiClientLib.checkInitiatorName
      Builtins.sleep(sl)

      return false if Abort()

      if Mode.auto || Mode.commandline
        return false unless IscsiClientLib.getServiceStatus
      end

      # try auto login to target
      IscsiClientLib.autoLogOn
      Builtins.sleep(sl)

      # read current settings
      #    if(!IscsiClientLib::autoLogOn()) return false;
      Progress.NextStage

      # read config file
      if IscsiClientLib.readSessions == false
        Report.Error(Message.CannotReadCurrentSettings)
        return false
      end
      Builtins.sleep(sl)

      return false if Abort()
      @modified = false
      true
    end

    # Write all iscsi-client settings
    # @return true on success
    def Write
      # IscsiClient read dialog caption
      caption = _("Saving iSCSI Initiator Configuration")

      # TODO: FIXME And set the right number of stages

      sl = 500
      Builtins.sleep(sl)

      descr = [
        # Progress stage 1/2
        _("Write AutoYaST settings"),
        # Progress stage 2/2
        _("Set up service status")
      ]
      descr = Builtins.remove(descr, 0) if !(Mode.autoinst || Mode.autoupgrade)
      # TODO: FIXME Names of real stages
      # We do not set help text here, because it was set outside
      Progress.New(caption, " ", Builtins.size(descr), descr, [], "")

      if Mode.autoinst || Mode.autoupgrade
        return false if Abort()
        Progress.NextStage
        IscsiClientLib.autoyastPrepare
        IscsiClientLib.autoyastWrite
        Builtins.sleep(sl)
      end

      return false if Abort()
      Progress.NextStage
      # set open-iscsi service status
      return false unless save_status
      Builtins.sleep(sl)

      return false if Abort()
      Progress.NextStage
      if Stage.initial &&
          Ops.greater_than(Builtins.size(IscsiClientLib.sessions), 0)
        Packages.addAdditionalPackage("open-iscsi")
      end
      Builtins.sleep(sl)

      true
    end

    # Saves service status (start mode and starts/stops the service)
    #
    # @note For AutoYaST and for command line actions, it uses the old way for
    # backward compatibility, see {IscsiClientLib#setServiceStatus}. When the
    # service is configured by using the UI, it directly saves the service, see
    # {Yast2::SystemService#save}.
    def save_status
      if Mode.auto || Mode.commandline
        IscsiClientLib.setServiceStatus
      else
        services.save
      end
    end

    # Get all iscsi-client settings from the first parameter
    # (For use by autoinstallation.)
    # @param [Hash] settings The YCP structure to be imported.
    # @return [Boolean] True on success
    def Import(settings)
      settings = deep_copy(settings)
      IscsiClientLib.ay_settings = deep_copy(settings)
      true
    end

    # Create a textual summary and a list of unconfigured cards
    # @return summary of the current configuration
    def Summary
      # TODO: FIXME: your code here...
      # Configuration summary text for autoyast
      [IscsiClientLib.Overview, []]
    end

    # Create an overview table with all configured cards
    # @return table items
    def Overview
      # TODO: FIXME: your code here...
      []
    end

    # Return packages needed to be installed and removed during
    # Autoinstallation to ensure module has all needed software
    # installed.
    # @return [Hash] with 2 lists.
    def AutoPackages
      { "install" => ["open-iscsi", "iscsiuio"], "remove" => [] }
    end

    publish :variable => :configured, :type => "boolean"
    publish :function => :Modified, :type => "boolean ()"
    publish :variable => :modified, :type => "boolean"
    publish :variable => :proposal_valid, :type => "boolean"
    # FIXME: write_only it is not used anymore
    publish :variable => :write_only, :type => "boolean"
    publish :variable => :AbortFunction, :type => "boolean ()"
    publish :function => :Abort, :type => "boolean ()"
    publish :function => :Export, :type => "map ()"
    publish :function => :Read, :type => "boolean ()"
    publish :function => :Write, :type => "boolean ()"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Summary, :type => "list ()"
    publish :function => :Overview, :type => "list ()"
    publish :function => :AutoPackages, :type => "map ()"
  end

  IscsiClient = IscsiClientClass.new
  IscsiClient.main
end
