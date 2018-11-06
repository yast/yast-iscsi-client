#!/usr/bin/env rspec
require_relative '../src/modules/IscsiClientLib'

describe Yast::IscsiClientLibClass do
  subject do
    @iscsilib = Yast::IscsiClientLibClass.new
    @iscsilib.main()
    @iscsilib
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
end
