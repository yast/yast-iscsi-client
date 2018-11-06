#!/usr/bin/env rspec
require_relative '../src/modules/IscsiClientLib'

describe Yast::IscsiClientLibClass do
  before :each do
    @iscsilib = Yast::IscsiClientLibClass.new
    @iscsilib.main
  end

  describe "#ScanDiscovered for iscsiadm -m session -P 1" do
    context "with Current Portal: and Persistent Portal: differ" do
      it "returns list of connected targets with IPs of Persistent Portal" do
        expect(@iscsilib.ScanDiscovered(
                                        ["Target: iqn.2013-10.de.suse:test_file1",
                                         "\tCurrent Portal: 10.13.67.182:3260,1",
                                         "\tPersistent Portal: 10.120.66.182:3260,1",
                                         "\t\t**********",
                                         "\t\tInterface:",
                                         "\t\t**********",
                                         "\t\tIface Name: default",
                                         "\t\tIface Transport: tcp",
                                         "\t\tIface Initiatorname: iqn.1996-04.de.suse:01:19eacab02a1d",
                                         "\t\tIface IPaddress: <empty>",
                                         "\t\tIface HWaddress: <empty>",
                                         "\t\tIface Netdev: <empty>",
                                         "\t\tSID: 1",
                                         "\t\tiSCSI Connection State: TRANSPORT WAIT",
                                         "\t\tiSCSI Session State: FREE",
                                         "\t\tInternal iscsid Session State: REOPEN", "",
                                         "Target: iqn.2013-10.de.suse:test_file2",
                                         "\tCurrent Portal: [2620:113:80c0:890:e051:56:73c7:9171]:3260,1",
                                         "\tPersistent Portal: [2620:113:80c0:8080:e051:f9ea:73c7:9171]:3260,1",
                                         "\t\t**********",
                                         "\t\tInterface:",
                                         "\t\t**********",
                                         "\t\tIface Name: default",
                                         "\t\tIface Transport: tcp",
                                         "\t\tIface Initiatorname: iqn.1996-04.de.suse:01:19eacab02a1d",
                                         "\t\tIface IPaddress: <empty>",
                                         "\t\tIface HWaddress: <empty>",
                                         "\t\tIface Netdev: <empty>",
                                         "\t\tSID: 1",
                                         "\t\tiSCSI Connection State: TRANSPORT WAIT",
                                         "\t\tiSCSI Session State: FREE",
                                         "\t\tInternal iscsid Session State: REOPEN", ""]
        )).to eq(
                                                ["10.120.66.182:3260 iqn.2013-10.de.suse:test_file1 default",
                                                 "[2620:113:80c0:8080:e051:f9ea:73c7:9171]:3260 iqn.2013-10.de.suse:test_file2 default"]
        )
      end
    end
  end

  describe "#ScanDiscovered for iscsiadm -m node -P 1" do
    context "with Portal:" do
      it "returns list of discovered targets with IPs of Portal" do
        expect(@iscsilib.ScanDiscovered(
                                        ["Target: iqn.2013-10.de.suse:test_file2",
                                         "\tPortal: [fe80::a00:27ff:fe1b:a7fe]:3260,1",
                                         "\t\tIface Name: default",
                                         "\tPortal: [2620:113:80c0:8080:e051:f9ea:73c7:9171]:3260,1",
                                         "\t\tIface Name: default",
                                         "\tPortal: 10.120.66.182:3260,1",
                                         "\t\tIface Name: default",
                                         "\tPortal: [2620:113:80c0:8080:a00:27ff:fe1b:a7fe]:3260,1",
                                         "\t\tIface Name: default"]
        )). to eq(
                                                  [
                                                    "[2620:113:80c0:8080:e051:f9ea:73c7:9171]:3260 iqn.2013-10.de.suse:test_file2 default",
                                                    "10.120.66.182:3260 iqn.2013-10.de.suse:test_file2 default",
                                                    "[2620:113:80c0:8080:a00:27ff:fe1b:a7fe]:3260 iqn.2013-10.de.suse:test_file2 default"
                                                  ]
        )
      end
    end
  end

end
