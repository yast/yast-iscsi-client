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
    end

    let(:args) { ["Write"] }
    let(:session) { false }

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
        let(:session) { true }

        context "and there is a systemd unit for the iscsiuio socket" do
          it "enables iscsi service and the iscsiuio socket" do
          end
        end

        context "but there is no systemd unit for the iscsiuio socket" do
          it "enables iscsi service and the iscsiuio service" do
          end
        end
      end

      context "and iscsiuio is not relevant in this system" do
        let(:session) { false }

        it "enables iscsi service but not iscsiuio" do
        end
      end
    end
  end
end
