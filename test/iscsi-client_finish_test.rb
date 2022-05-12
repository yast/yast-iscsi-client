#!/usr/bin/env rspec

require_relative "test_helper"
require_relative "../src/clients/iscsi-client_finish"

describe Yast::IscsiClientFinishClient do
  subject { described_class.new }

  describe "#main when func is 'Write'" do
    before do
      allow(Yast::WFM).to receive(:Args).with(no_args).and_return(args)
      allow(Yast::WFM).to receive(:Args) { |n| n.nil? ? args : args[n] }

      # Mock copying of the open-iscsi database to avoid side effects
      allow(Yast::WFM).to receive(:Execute)

      allow(Yast::IscsiClientLib).to receive(:sessions).and_return session
      allow(Yast::IscsiClientLib).to receive(:iscsiuio_relevant?).and_return iscsiuio
      allow(Yast2::Systemd::Socket).to receive(:find)
      allow(Yast2::Systemd::Socket).to receive(:find)
        .with("iscsiuio")
        .and_return(iscsiuio_socket)

      # The agent .probe.netcard is used to inspect the network cards in the system, this
      # intercepts that call and mocks the result based on the scenario we want to simulate
      allow(Yast::SCR).to receive(:Read).and_call_original
      allow(Yast::SCR).to receive(:Read).with(Yast::Path.new(".probe.netcard"))
        .and_return probe_netcard
    end

    let(:args) { ["Write"] }
    let(:session) { false }
    let(:iscsiuio) { false }
    let(:iscsiuio_socket) { nil }
    let(:probe_netcard) { [] }

    context "if there are no active iSCSI sessions" do
      let(:session) { [] }

      it "does not enable any service or socket" do
        expect(Yast2::Systemd::Socket).to_not receive(:find)
        expect(Yast::Service).to_not receive(:Enable)

        result = subject.main
        expect(result).to be_nil
      end
    end

    context "if there is any active iSCSI session" do
      let(:session) { ["session0", "session1"] }

      context "and iscsiuio may be relevant in this system" do
        let(:iscsiuio) { true }

        context "and there is a systemd unit for the iscsiuio socket" do
          let(:iscsiuio_socket) { instance_double(Yast2::Systemd::Socket, enable: true) }

          it "enables iscsi service and the iscsiuio socket but not the iscsiuio service" do
            expect(Yast::Service).to receive(:Enable).with("iscsid")
            expect(Yast::Service).to receive(:Enable).with("iscsi")
            expect(Yast::Service).to_not receive(:Enable).with("iscsiuio")
            expect(iscsiuio_socket).to receive(:enable)

            subject.main
          end
        end

        context "but there is no systemd unit for the iscsiuio socket" do
          let(:iscsiuio_socket) { nil }

          it "enables iscsi service and the iscsiuio service" do
            expect(Yast::Service).to receive(:Enable).with("iscsid")
            expect(Yast::Service).to receive(:Enable).with("iscsi")
            expect(Yast::Service).to receive(:Enable).with("iscsiuio")

            subject.main
          end
        end
      end

      context "and iscsiuio is not relevant in this system" do
        let(:iscsiuio) { false }

        it "enables iscsi service but not the iscsiuio service" do
          expect(Yast::Service).to receive(:Enable).with("iscsid")
          expect(Yast::Service).to receive(:Enable).with("iscsi")
          expect(Yast2::Systemd::Socket).to_not receive(:find).with("iscsiuio")

          subject.main
        end
      end
    end
  end
end
