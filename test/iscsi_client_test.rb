#!/usr/bin/env rspec

require_relative "./test_helper"

Yast.import "IscsiClient"

describe Yast::IscsiClient do
  subject { described_class }

  let(:service) { instance_double("Yast2::SystemService", is_a?: true) }

  describe "#services" do
    before do
      allow(Yast2::SystemService).to receive(:find).with(anything).and_return(service)
    end

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
end
