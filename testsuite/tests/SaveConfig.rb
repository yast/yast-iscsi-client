# encoding: utf-8

module Yast
  class SaveConfigClient < Client
    def main
      Yast.include self, "testsuite.rb"

      @READ = {
        "target" => { "tmpdir" => "/tmp" },
        "etc"    => {
          "iscsid" => {
            "all" => {
              "comment" => "",
              "file"    => -1,
              "kind"    => "section",
              "name"    => "",
              "type"    => -1,
              "value"   => [
                {
                  "comment" => "#\n" +
                    "# Open-iSCSI default configuration.\n" +
                    "# Could be located at /etc/iscsid.conf or ~/.iscsid.conf\n" +
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
          }
        }
      }
      TESTSUITE_INIT([@READ, {}, {}], nil)

      Yast.import "IscsiClientLib"

      TEST(lambda { IscsiClientLib.getConfig }, [@READ, {}, {}], nil)
      TEST(lambda do
        IscsiClientLib.saveConfig("incuser", "incpass", "outuser", "outpass")
      end, [
        @READ,
        {},
        {}
      ], nil)
      TEST(lambda { IscsiClientLib.oldConfig }, [@READ, {}, {}], nil)

      nil
    end
  end
end

Yast::SaveConfigClient.new.main
