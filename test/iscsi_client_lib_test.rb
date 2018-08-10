#!/usr/bin/env rspec

require_relative "test_helper"
require_relative "../src/modules/IscsiClientLib"

describe Yast::IscsiClientLibClass do
  subject { described_class.new }

  describe "#getServiceStatus" do
    before do
      allow(Yast::Service).to receive(:Stop).with(anything)
      allow(Yast::Service).to receive(:active?).with(anything)
      allow(Yast::SystemdSocket).to receive(:find!).with(anything)
      allow(subject).to receive(:socketActive?)
      allow(subject.log).to receive(:error)
    end

    context "for iscsid.socket" do
      let(:iscsid_socket) { double("iscsid.socket", start: true) }

      before do
        allow(Yast::SystemdSocket).to receive(:find!).with("iscsid").and_return(iscsid_socket)
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
end
