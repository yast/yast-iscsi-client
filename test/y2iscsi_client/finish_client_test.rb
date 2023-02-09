#!/usr/bin/env rspec

require_relative "../test_helper"
require "y2iscsi_client/finish_client"

describe Y2IscsiClient::FinishClient do
  describe "#write" do
    before do
      Yast::Installation.destdir = "/mnt"
      allow(Yast::IscsiClientLib).to receive(:sessions).and_return sessions
      allow(File).to receive(:directory?).with("/etc/iscsi").and_return config_exists
    end

    let(:sessions) { [] }
    let(:config_exists) { false }

    context "if there is an /etc/iscsi directory in the int-sys" do
      let(:config_exists) { true }

      it "copies the content of /etc/iscsi to the target system" do
        expect(Yast::Execute).to receive(:locally!) do |*args|
          expect(args.join(" "))
            .to eq "mkdir -p /mnt/etc/iscsi && cp -a /etc/iscsi/* /mnt/etc/iscsi/"
        end

        subject.write
      end

      it "fails gracefully (no exception or crash) if copying /etc/iscsi fails" do
        allow(Yast::Execute).to receive(:locally!).with(any_args, "/mnt/etc/iscsi/")
          .and_raise Cheetah::ExecutionFailed.new("cmd", 1, "", "Something went wrong")

        expect { subject.write }.to_not raise_error
      end
    end

    context "if there is no /etc/iscsi directory in the int-sys" do
      let(:config_exists) { false }

      it "does not copy any file" do
        expect(Yast::Execute).to_not receive(:locally!)
        subject.write
      end
    end

    context "if there are no active iSCSI sessions" do
      let(:sessions) { [] }

      it "does not modify any socket or service" do
        expect(Yast::Service).to_not receive(:Enable)
        expect(Yast2::Systemd::Socket).to_not receive(:find)

        subject.write
      end
    end

    context "if there are active iSCSI sessions" do
      let(:sessions) { ["1.1.1.1:2222 iqn.something default"] }

      before do
        allow(Yast2::Systemd::Socket).to receive(:find).and_return nil
        allow(Yast::Service).to receive(:Enable)
        allow(Yast::IscsiClientLib).to receive(:iscsiuio_relevant?).and_return uio
      end

      context "and the iscsiuio service is not needed" do
        let(:uio) { false }

        it "enables the iscsid and iscsi services" do
          expect(Yast::Service).to receive(:Enable).with("iscsid")
          expect(Yast::Service).to receive(:Enable).with("iscsi")
          subject.write
        end

        it "it does not enable the iscsiuio service nor socket" do
          expect(Yast2::Systemd::Socket).to_not receive(:find).with("iscsiuio")
          expect(Yast::Service).to_not receive(:Enable).with("iscsiuio")
          subject.write
        end
      end

      context "and the iscsiuio service is needed" do
        let(:uio) { true }

        before do
          allow(Yast2::Systemd::Socket).to receive(:find).with("iscsiuio").and_return(uio_socket)
        end

        context "and there is an iscsiuio socket" do
          let(:uio_socket) { instance_double(Yast2::Systemd::Socket) }

          it "enables the iscsid and iscsi services and the iscsiuio socket" do
            expect(Yast::Service).to receive(:Enable).with("iscsid")
            expect(Yast::Service).to receive(:Enable).with("iscsi")
            expect(uio_socket).to receive(:enable)
            subject.write
          end

          it "it does not enable the iscsiuio service" do
            allow(uio_socket).to receive(:enable)
            expect(Yast::Service).to_not receive(:Enable).with("iscsiuio")
            subject.write
          end
        end

        context "and there is no iscsiuio socket" do
          let(:uio_socket) { nil }

          it "enables the iscsid, iscsi and iscsiuio services" do
            expect(Yast::Service).to receive(:Enable).with("iscsid")
            expect(Yast::Service).to receive(:Enable).with("iscsi")
            expect(Yast::Service).to receive(:Enable).with("iscsiuio")
            subject.write
          end
        end
      end
    end
  end
end
