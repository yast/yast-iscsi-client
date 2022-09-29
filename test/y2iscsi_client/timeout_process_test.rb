#!/usr/bin/env rspec

require_relative "../test_helper"
require "y2iscsi_client/timeout_process"

describe Y2IscsiClient::TimeoutProcess do
  describe ".run" do
    before do
      allow(Yast::Popup).to receive(:Error)
    end

    context "when command succeed" do
      it "returns true and its stdout" do
        expect(described_class.run(["echo", "15\n50"])).to eq([true, ["15", "50"]])
      end
    end

    context "when command failed" do
      it "shows error popup" do
        expect(Yast::Popup).to receive(:Error)

        described_class.run(["false"])
      end

      it "returns false and its stderr" do
        expect(described_class.run(["false"])).to eq([false, []])
      end
    end

    context "when command runs after timeout" do
      it "shows error popup" do
        expect(Yast::Popup).to receive(:Error).with("Command timed out")

        described_class.run(["sleep", "10"], timeout: 1)
      end

      it "returns false and its stderr" do
        expect(described_class.run(["sleep", "10"], timeout: 1)).to eq([false, []])
      end
    end
  end
end
