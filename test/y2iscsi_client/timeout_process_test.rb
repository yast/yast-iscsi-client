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
      # a command that produces stdout AND stderr AND fails
      let(:command) { ["sh", "-c", "echo Copying data; echo >&2 Giving up; false"] }

      it "shows error popup with its stderr" do
        expect(Yast::Popup).to receive(:Error).with("Giving up\n")

        described_class.run(command)
      end

      it "does not show any popup if silent mode was requested" do
        expect(Yast::Popup).to_not receive(:Error)

        described_class.run(command, silent: true)
      end

      it "returns false and its stdout" do
        expect(described_class.run(command)).to eq([false, ["Copying data"]])
      end
    end

    context "when command runs after timeout" do
      # a command that produces stdout AND stderr AND takes a long time
      let(:command) { ["sh", "-c", "echo Copying data; echo >&2 Mars is too far; sleep 999"] }

      it "shows generic error popup if silent mode was not requested" do
        expect(Yast::Popup).to receive(:Error).with("Command timed out")

        described_class.run(command, seconds: 1)
      end

      it "does not show any popup if silent mode was requested" do
        expect(Yast::Popup).to_not receive(:Error)

        described_class.run(command, seconds: 1, silent: true)
      end

      it "returns false and its stdout" do
        expect(described_class.run(command, seconds: 1)).to eq([false, ["Copying data"]])
      end
    end
  end
end
