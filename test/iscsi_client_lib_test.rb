#!/usr/bin/env rspec

require_relative "test_helper"
Yast.import "IscsiClientLib"

describe Yast::IscsiClientLib do
  subject { described_class }

  before do
    subject.main
  end

  describe "#getServiceStatus" do
    before do
      allow(Yast::Service).to receive(:Stop).with(anything)
      allow(Yast::Service).to receive(:active?).with(anything)
      allow(Yast2::Systemd::Socket).to receive(:find!).with(anything)
      allow(subject).to receive(:socketActive?)
      allow(subject.log).to receive(:error)
    end

    context "for iscsid.socket" do
      let(:iscsid_socket) { double("iscsid.socket", start: true) }

      before do
        allow(Yast2::Systemd::Socket).to receive(:find!).with("iscsid").and_return(iscsid_socket)
        allow(subject).to receive(:socketActive?).with(iscsid_socket).and_return(socket_status)
      end

      context "when iscsid.socket and iscsid.service are active" do
        let(:socket_status) { true }

        before do
          allow(Yast::Service).to receive(:active?).with("iscsid").and_return(true)
        end

        it "does not start the socket nor the service" do
          expect(iscsid_socket).to_not receive(:start)
          expect(Yast::Service).to_not receive(:Stop).with("iscsid")

          subject.getServiceStatus
        end
      end

      context "when iscsid.socket is not active" do
        let(:socket_status) { false }

        context "and socket is availbale" do
          it "starts iscsid.socket" do
            expect(iscsid_socket).to receive(:start)

            subject.getServiceStatus
          end

          context "but iscsid.service is active" do
            before do
              allow(Yast::Service).to receive(:active?).with("iscsid").and_return(true)
            end

            it "stops iscsid.service" do
              expect(Yast::Service).to receive(:Stop).with("iscsid")

              subject.getServiceStatus
            end
          end
        end

        context "but socket is not availbale" do
          let(:iscsid_socket) { nil }

          it "logs an error" do
            expect(subject.log).to receive(:error).with("Cannot start iscsid.socket")

            subject.getServiceStatus
          end
        end
      end
    end
  end

  describe ".autoyastWrite" do
    it "calls iscsiadm discovery" do
      subject.ay_settings = {
        "targets" => [
          { "iface" => "eth0", "portal" => "magic" },
          { "iface" => "eth1", "portal" => "portal 1" }
        ]
      }

      allow(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash_output"), anything)
        .and_return("exit" => 0, "stdout" => "", "stderr" => "")

      expect(Yast::SCR).to receive(:Execute).with(
        Yast::Path.new(".target.bash"),
        "LC_ALL=POSIX /sbin/iscsiadm -m discovery -I eth0 -I eth1 -t st -p magic"
      )
      expect(Yast::SCR).to receive(:Execute).with(
        Yast::Path.new(".target.bash"),
        "LC_ALL=POSIX /sbin/iscsiadm -m discovery -I eth0 -I eth1 -t st -p portal\\ 1"
      )

      subject.autoyastWrite
    end
  end

  describe "#ipEqual" do
    context "with IPv4 arguments not matching" do
      it "returns false" do
        expect(subject.ipEqual?("213:23:", "...")).to eq(false)
      end
    end
    context "with equal IPv4 addresses (without port)" do
      it "returns true" do
        expect(subject.ipEqual?("10.10.10.1", "10.10.10.1")).to eq(true)
      end
    end
    context "with equal IPv4 addresses and equal port" do
      it "returns true" do
        expect(subject.ipEqual?("10.10.10.1:345", "10.10.10.1:345")).to eq(true)
      end
    end
    context "with equal IPv4 addresses and different ports" do
      it "returns false" do
        expect(subject.ipEqual?("10.10.10.1:345", "10.10.10.1:500")).to eq(false)
      end
    end
    context "with invalid IPv6 arguments" do
      it "returns false" do
        expect(subject.ipEqual?("[213:23:]", "...")).to eq(false)
      end
    end
    context "with invalid IPv6 arguments not matching" do
      it "returns false" do
        expect(subject.ipEqual?("[???]", "[***]")).to eq(false)
      end
    end
    context "with 2 empty arguments" do
      it "returns false" do
        expect(subject.ipEqual?("", "")).to eq(false)
      end
    end
    context "with empty argument session IP" do
      it "returns false" do
        expect(subject.ipEqual?("", "10.10.10.1:500")).to eq(false)
      end
    end
    context "with empty argument current IP" do
      it "returns false" do
        expect(subject.ipEqual?("[2620:0113:1c0:8080:4ec:544a:000d:3d62]", "")).to eq(false)
      end
    end
    context "with nil arguments" do
      it "returns false" do
        expect(subject.ipEqual?(nil, nil)).to eq(false)
      end
    end
    context "with one nil argument" do
      it "returns false" do
        expect(subject.ipEqual?(nil, "10.10.10.1:500")).to eq(false)
      end
    end
    context "with equal (but different string) and valid IPv6 arguments (without port)" do
      it "returns true" do
        expect(subject.ipEqual?("[2620:0113:1c0:8080:4ec:544a:000d:3d62]",
          "[2620:113:1c0:8080:4ec:544a:d:3d62]")).to eq(true)
      end
    end
    context "with equal (same string) and valid IPv6 arguments (without port)" do
      it "returns true" do
        expect(subject.ipEqual?("[2620:113:1c0:8080:4ec:544a:000d:3d62]",
          "[2620:113:1c0:8080:4ec:544a:d:3d62]")).to eq(true)
      end
    end
    context "with equal (but different string) and valid IPv6 arguments and equal ports" do
      it "returns true" do
        expect(subject.ipEqual?("[0020:0113:80c0:8080:0:544a:3b9d:3d62]:456",
          "[20:113:80c0:8080::544a:3b9d:3d62]:456")).to eq(true)
      end
    end
    context "with equal (different string, one abbreviated) valid IPv6 arguments" do
      it "returns true" do
        expect(subject.ipEqual?("[::1]", "[0:0:0:0:0:0:0:1]")).to eq(true)
      end
    end
    context "with equal (but different string) IPv6 arguments and different ports" do
      it "returns false" do
        expect(subject.ipEqual?("[2620:0113:80c0:8080:54ec:004a:3b9d:3d62]:456",
          "[2620:113:80c0:8080:54ec:4a:3b9d:3d62]:4")).to eq(false)
      end
    end
    context "with equal (same string) IPv6 arguments and different ports" do
      it "returns false" do
        expect(subject.ipEqual?("[2620:113:80c0:8080:54ec:544a:3b9d:3d62]:456",
          "[2620:113:80c0:8080:54ec:544a:3b9d:3d62]:4")).to eq(false)
      end
    end
  end

  describe "#getConfig,#saveConfig,#oldConfig" do
    let(:etc_iscsid_all) { Yast::Path.new ".etc.iscsid.all" }
    let(:etc_iscsid)     { Yast::Path.new ".etc.iscsid" }
    let(:read_data) do
      {
        "comment" => "",
        "file"    => -1,
        "kind"    => "section",
        "name"    => "",
        "type"    => -1,
        "value"   => [
          {
            "comment" => "#\n" \
            "# Open-iSCSI default configuration.\n" \
            "# Could be located at /etc/iscsid.conf or ~/.iscsid.conf\n" \
            "#\n",
            "kind"    => "value",
            "name"    => "node.active_cnx",
            "type"    => 1,
            "value"   => "1"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.startup",
            "type"    => 1,
            "value"   => "manual"
          },
          {
            "comment" => "#node.session.auth.username = dima\n#node.session.auth.password = aloha\n",
            "kind"    => "value",
            "name"    => "node.session.timeo.replacement_timeout",
            "type"    => 1,
            "value"   => "120"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.err_timeo.abort_timeout",
            "type"    => 1,
            "value"   => "10"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.err_timeo.reset_timeout",
            "type"    => 1,
            "value"   => "30"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.InitialR2T",
            "type"    => 1,
            "value"   => "No"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.ImmediateData",
            "type"    => 1,
            "value"   => "Yes"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.FirstBurstLength",
            "type"    => 1,
            "value"   => "262144"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.MaxBurstLength",
            "type"    => 1,
            "value"   => "16776192"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.DefaultTime2Wait",
            "type"    => 1,
            "value"   => "0"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.DefaultTime2Retain",
            "type"    => 1,
            "value"   => "0"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.MaxConnections",
            "type"    => 1,
            "value"   => "0"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.cnx[0].iscsi.HeaderDigest",
            "type"    => 1,
            "value"   => "None"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.cnx[0].iscsi.DataDigest",
            "type"    => 1,
            "value"   => "None"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.cnx[0].iscsi.MaxRecvDataSegmentLength",
            "type"    => 1,
            "value"   => "65536"
          }
        ]
      }
    end

    let(:written_data) do
      {
        "comment" => "",
        "file"    => -1,
        "kind"    => "section",
        "name"    => "",
        "type"    => -1,
        "value"   => [
          {
            "comment" => "#\n# Open-iSCSI default configuration.\n# Could be located at /etc/iscsid.conf or ~/.iscsid.conf\n#\n",
            "kind"    => "value",
            "name"    => "node.active_cnx",
            "type"    => 1,
            "value"   => "1"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.startup",
            "type"    => 1,
            "value"   => "manual"
          },
          {
            "comment" => "#node.session.auth.username = dima\n#node.session.auth.password = aloha\n",
            "kind"    => "value",
            "name"    => "node.session.timeo.replacement_timeout",
            "type"    => 1,
            "value"   => "120"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.err_timeo.abort_timeout",
            "type"    => 1,
            "value"   => "10"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.err_timeo.reset_timeout",
            "type"    => 1,
            "value"   => "30"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.InitialR2T",
            "type"    => 1,
            "value"   => "No"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.ImmediateData",
            "type"    => 1,
            "value"   => "Yes"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.FirstBurstLength",
            "type"    => 1,
            "value"   => "262144"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.MaxBurstLength",
            "type"    => 1,
            "value"   => "16776192"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.DefaultTime2Wait",
            "type"    => 1,
            "value"   => "0"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.DefaultTime2Retain",
            "type"    => 1,
            "value"   => "0"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.session.iscsi.MaxConnections",
            "type"    => 1,
            "value"   => "0"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.cnx[0].iscsi.HeaderDigest",
            "type"    => 1,
            "value"   => "None"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.cnx[0].iscsi.DataDigest",
            "type"    => 1,
            "value"   => "None"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "node.cnx[0].iscsi.MaxRecvDataSegmentLength",
            "type"    => 1,
            "value"   => "65536"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "discovery.sendtargets.auth.authmethod",
            "type"    => 1,
            "value"   => "CHAP"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "discovery.sendtargets.auth.username_in",
            "type"    => 1,
            "value"   => "incuser"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "discovery.sendtargets.auth.password_in",
            "type"    => 1,
            "value"   => "incpass"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "discovery.sendtargets.auth.username",
            "type"    => 1,
            "value"   => "outuser"
          },
          {
            "comment" => "",
            "kind"    => "value",
            "name"    => "discovery.sendtargets.auth.password",
            "type"    => 1,
            "value"   => "outpass"
          }
        ]
      }
    end

    it "mimics a legacy test" do
      allow(Yast::SCR).to receive(:Read)
        .with(etc_iscsid_all).and_return(read_data)
      expect(subject.getConfig).to eq(read_data.fetch("value"))

      expect(Yast::SCR).to receive(:Write)
        .with(etc_iscsid_all, written_data).and_return(true)
      expect(Yast::SCR).to receive(:Write)
        .with(etc_iscsid, nil).and_return(true)
      expect(subject.saveConfig("incuser", "incpass", "outuser", "outpass"))
        .to eq(nil)

      expect(Yast::SCR).to receive(:Write)
        .with(etc_iscsid_all, read_data).and_return(true)
      expect(Yast::SCR).to receive(:Write)
        .with(etc_iscsid, nil).and_return(true)
      expect(subject.oldConfig).to eq(nil)
    end
  end

  describe "#ScanDiscovered for iscsiadm -m session -P 1" do
    context "with Current Portal: and Persistent Portal: differ" do
      it "returns list of connected targets with IPs of Persistent Portal" do
        expect(subject.ScanDiscovered(
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
        expect(subject.ScanDiscovered(
                 ["Target: iqn.2013-10.de.suse:test_file2",
                  "\tPortal: [fe80::a00:27ff:fe1b:a7fe]:3260,1",
                  "\t\tIface Name: default",
                  "Target: iqn.2013-10.de.suse:test_file2",
                  "\tPortal: [2620:113:80c0:8080:e051:f9ea:73c7:9171]:3260,1",
                  "\t\tIface Name: default",
                  "Target: iqn.2013-10.de.suse:test_file2",
                  "\tPortal: 10.120.66.182:3260,1",
                  "Target: iqn.2013-10.de.suse:test_file2",
                  "\tPortal: [2620:113:80c0:8080:a00:27ff:fe1b:a7fe]:3260,1",
                  "Target: iqn.2018-06.de.suse.zeus:01",
                  "\tPortal: 192.168.20.20:3260,2",
                  "\t\tIface Name: default",
                  "\tPortal: 192.168.10.20:3260,1",
                  "\t\tIface Name: default"]
        )). to eq(
          [
            "[2620:113:80c0:8080:e051:f9ea:73c7:9171]:3260 iqn.2013-10.de.suse:test_file2 default",
            "10.120.66.182:3260 iqn.2013-10.de.suse:test_file2 default",
            "[2620:113:80c0:8080:a00:27ff:fe1b:a7fe]:3260 iqn.2013-10.de.suse:test_file2 default",
            "192.168.20.20:3260 iqn.2018-06.de.suse.zeus:01 default",
            "192.168.10.20:3260 iqn.2018-06.de.suse.zeus:01 default"
          ]
        )
      end
    end
  end

  describe "#getiBFT" do
    context "when filtering output of 'iscsiadm -m fw'" do
      it "returns data in form of a map " do
        allow(Yast::Arch).to receive(:architecture).and_return("x86_64")
        allow(subject).to receive(:getFirmwareInfo)
          .and_return("# BEGIN RECORD 2.0-872\n"\
                     "iface.bootproto = STATIC\n"\
                     "iface.transport_name = tcp\n"\
                     "iface.hwaddress = 00:00:c9:b1:bc:7f\n"\
                     "iface.initiatorname = iqn.2011-05.com.emulex:eraptorrfshoneport1\n"\
                     "iface.ipaddress = 2620:0113:80c0:8000:000c:0000:0000:04dc\n"\
                     "node.conn[0].address = 172.0.21.6\n"\
                     "node.conn[0].port = 3260\n"\
                     "node.name = iqn.1986-03.com.ibm:sn.135061874\n"\
                     "# END RECORD\n")

        ibft_data = subject.getiBFT

        expect(ibft_data).to eq(
          "iface.bootproto"      => "STATIC",
          "iface.hwaddress"      => "00:00:c9:b1:bc:7f",
          "iface.initiatorname"  => "iqn.2011-05.com.emulex:eraptorrfshoneport1",
          "iface.transport_name" => "tcp",
          "iface.ipaddress"      => "2620:0113:80c0:8000:000c:0000:0000:04dc",
          "node.conn[0].address" => "172.0.21.6",
          "node.conn[0].port"    => "3260",
          "node.name"            => "iqn.1986-03.com.ibm:sn.135061874"
        )
      end
    end

    context "when could not get list of targets from firmware" do
      it "returns an empty map " do
        allow(Yast::Arch).to receive(:architecture).and_return("x86_64")
        allow(subject).to receive(:getFirmwareInfo).and_return("")

        ibft_data = subject.getiBFT

        expect(ibft_data).to eq({})
      end
    end

    context "when not on x86 hardware" do
      it "returns an empty map " do
        allow(Yast::Arch).to receive(:architecture).and_return("s390_64")

        ibft_data = subject.getiBFT

        expect(ibft_data).to eq({})
      end
    end

  end
end
