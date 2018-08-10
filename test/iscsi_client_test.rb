#!/usr/bin/env rspec

require_relative "./test_helper"
require_relative "../src/modules/IscsiClient"

Yast.import "IscsiClient"

describe Yast::IscsiClient do
  subject(:iscsi_client) { described_class }

  before do
    allow(Yast2::SystemService).to receive(:find).with(anything).and_return(service)
  end

  let(:service) { instance_double(Yast2::SystemService, save: true, is_a?: true) }
  let(:services) { instance_double(Yast2::CompoundService, save: true) }
  let(:auto) { false }
  let(:commandline) { false }

  describe "#services" do
    it "includes iscsi, iscsid, and iscsiuio" do
      expect(Yast2::SystemService).to receive(:find).with("iscsi")
      expect(Yast2::SystemService).to receive(:find).with("iscsid")
      expect(Yast2::SystemService).to receive(:find).with("iscsiuio")

      subject.services
    end

    it "returns a compound service" do
      expect(subject.services).to be_a(Yast2::CompoundService)
    end
  end

  describe "#Read" do
    before do
      allow(Yast::Progress).to receive(:New)
      allow(Yast::Progress).to receive(:NextStage)
      allow(Yast::Confirm).to receive(:MustBeRoot).and_return(true)
      allow(Yast::NetworkService).to receive(:RunnungNetworkPopup).and_return(true)
      allow(Yast::Builtins).to receive(:sleep)
      allow(Yast::Builtins).to receive(:y2milestone)

      allow(Yast::IscsiClientLib).to receive(:getiBFT).and_return(true)
      allow(Yast::IscsiClientLib).to receive(:checkInitiatorName).and_return(true)
      allow(Yast::IscsiClientLib).to receive(:autoLogOn)
      allow(Yast::IscsiClientLib).to receive(:readSession).and_return(true)

      allow(Yast::Mode).to receive(:auto) { auto }
      allow(Yast::Mode).to receive(:commandline) { commandline }

      allow(iscsi_client).to receive(:Abort).and_return(false)
      allow(iscsi_client).to receive(:installed_packages).and_return(true)

      iscsi_client.main
    end

    shared_examples "old behavior" do
      it "calls to IscsiClientLib#getServiceStatus" do
        expect(Yast::IscsiClientLib).to receive(:getServiceStatus)

        iscsi_client.Read
      end
    end

    context "when running in command line" do
      let(:commandline) { true }

      include_examples "old behavior"
    end

    context "when running in AutoYaST mode" do
      let(:auto) { true }

      include_examples "old behavior"
    end

    context "when running in normal mode" do
      it "does not call to IscsiClientLib#getServiceStatus" do
        expect(Yast::IscsiClientLib).to_not receive(:getServiceStatus)

        iscsi_client.Read
      end
    end
  end

  describe "#Write" do
    before do
      allow(Yast::Progress).to receive(:New)
      allow(Yast::Progress).to receive(:NextStage)
      allow(Yast::Report).to receive(:Error)
      allow(Yast::Builtins).to receive(:sleep)
      allow(Yast::Stage).to receive(:initial).and_return(false)
      allow(Yast::Mode).to receive(:auto) { auto }
      allow(Yast::Mode).to receive(:commandline) { commandline }

      allow(iscsi_client).to receive(:Abort).and_return(false)

      iscsi_client.main
    end

    shared_examples "old behavior" do
      before do
        allow(Yast::IscsiClientLib).to receive(:autoyastPrepare)
        allow(Yast::IscsiClientLib).to receive(:autoyastWrite)
      end

      it "does not save the system service" do
        expect(service).to_not receive(:save)

        iscsi_client.Write
      end

      it "calls to IscsiClientLib#setServiceStatus" do
        expect(Yast::IscsiClientLib).to receive(:setServiceStatus)

        iscsi_client.Write
      end
    end

    context "when running in command line" do
      let(:commandline) { true }

      include_examples "old behavior"
    end

    context "when running in AutoYaST mode" do
      let(:auto) { true }

      include_examples "old behavior"
    end

    context "when running in normal mode" do
      before do
        allow(iscsi_client).to receive(:services).and_return(services)
      end

      it "does not call IscsiClientLib#setServiceStatus" do
        expect(Yast::IscsiClientLib).to_not receive(:setServiceStatus)

        iscsi_client.Write
      end

      it "saves system services" do
        expect(services).to receive(:save)

        iscsi_client.Write
      end
    end
  end
end
