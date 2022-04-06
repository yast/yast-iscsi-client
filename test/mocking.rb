# encoding: utf-8

# |***************************************************************************
# |
# | Copyright (c) [2022] SUSE LLC
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

# Convenience functions to mock stuff in the unit tests

# Description of a card to be used for mocking
#
# @return [Hash] with the same structure returned by the agent .probe.netcard
def probed_card(dev_name, driver, mac)
  {
    "dev_name" => dev_name, "dev_names" => [dev_name],
    "driver" => driver, "driver_module" => driver,
    "drivers" => [{ "active" => true, "modprobe" => true, "modules" => [[driver, ""]] }],
    "resource" => { "hwaddr" => [{ "addr" => mac }] }
  }
end

# Mocks a call done with the .target.bash_output agent
def mock_bash_out(command, result)
  path = Yast::Path.new(".target.bash_output")
  allow(Yast::SCR).to receive(:Execute).with(path, command).and_return result
end

# Mocks the call to the iscsi_offload command for a given interface
#
# @param card [String] name of the interface
# @param success [Boolean] whether offloading is supported for the card
# @param mac [String, nil] if success is true, mac addr to be included in the command output
def mock_iscsi_offload(card, success, mac = nil)
  result = { "stderr" => "" }
  if success
    result["exit"] = 0
    result["stdout"] = "#{mac} none\n"
  else
    result["exit"] = 2
    result["stdout"] = "iSCSI offloading not supported on interface #{card}\n"
  end

  mock_bash_out(/iscsi_offload #{card}/, result)
end

# Mocks a call to ifconfig done to check the IP of a concrete interface
#
# The behavior depends on the value of the 'ipaddr' argument:
#
# - If nil it works as if ifconfig is not installed, that's the default because that tool is
#   only available in the package "net-tools-deprecated".
# - If blank ("") it works as if the interface has no configured IP.
# - In other case, it emulates the output of ifconfig for a configured card.
#
# Note this emulates the output of ifconfig-2.X in which the IP is represented as
# "inet X.X.X.X". At the moment of writing, the yast2-iscsi-client code seems to be only
# adapted to parse the output of the old ifconfig-1.X (which used "inet addr X.X.X.X").
#
# @param dev_name [String] interface name
# @param ipaddr [String, nil]
def mock_ifconfig(dev_name, ipaddr = nil)
  result = { "exit" => 0, "stdout" => "", "stderr" => "" }

  if ipaddr
    result["stdout"] << "#{dev_name}: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500\n"
    if !ipaddr.empty?
      result["stdout"] << "      inet #{ipaddr}  netmask 255.255.255.0  broadcast 192.168.0.255\n"
    end
    result["stdout"] << <<EOF
      RX packets 927138  bytes 920436197 (877.7 MiB)
      TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
      device interrupt 17
EOF
  else
    result["exit"] = 127
    result["stderr"] = "sh: /usr/bin/ifconfig: No such file or directory\n"
  end

  mock_bash_out(/ifconfig #{dev_name}/, result)
end

# Mocks a call to "iscsiadm --mode node -P 1"
#
# @param ifaces [Array<String>] list of active iSCSI interfaces defined at /etc/iscsi/ifaces
def mock_iscsiadm_mode(ifaces)
  result = { "exit" => 0, "stdout" => "", "stderr" => "" }

  if ifaces.empty?
    result["exit"] = 21
    result["stderr"] = "iscsiadm: No records found\n"
  end

  ifaces.each do |iface|
    result["stdout"] << "Target: iqn.2013-10.de.suse:test_file1\n"
    result["stdout"] << "\tPortal: 192.168.99.99:3260,1\n"
    result["stdout"] << "\t\tIface Name: #{iface}\n"
  end

  mock_bash_out(/iscsiadm -m node -P 1/, result)
end
