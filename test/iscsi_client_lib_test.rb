require_relative "test_helper"

require_relative "../src/modules/IscsiClientLib"

describe Yast::IscsiClientLibClass do
  subject { described_class.new }

  describe "#getServiceStatus" do
    let(:iscsid_socket) { double("iscsid.socket", start: true) }

    before do
      allow(Yast::Service).to receive(:Stop).with(anything)
      allow(Yast::Service).to receive(:active?).with(anything)
      allow(Yast::SystemdSocket).to receive(:find!).with(anything)
      allow(subject).to receive(:socketActive?)
      allow(subject.log).to receive(:error)
    end

    context "when iscsid.socket and iscsid.service are active" do
      before do
        allow(Yast::Service).to receive(:active?).with("iscsid").and_return(true)
        allow(Yast::SystemdSocket).to receive(:find!).with("iscsid").and_return(iscsid_socket)
        allow(subject).to receive(:socketActive?).with(iscsid_socket).and_return(true)
      end

      it "does nothing" do
        expect(iscsid_socket).to_not receive(:start)
        expect(Yast::Service).to_not receive(:Stop).with("iscsid")

        subject.getServiceStatus
      end
    end

    context "when iscsid.socket is not active" do
      before do
        allow(Yast::SystemdSocket).to receive(:find!).with("iscsid").and_return(iscsid_socket)
        allow(subject).to receive(:socketActive?).with(iscsid_socket).and_return(false)
      end

      context "and socket is availbale" do
        it "start iscsid.socket" do
          expect(iscsid_socket).to receive(:start)

          subject.getServiceStatus
        end

        context "but iscsid.service is active" do
          before do
            allow(Yast::Service).to receive(:active?).with("iscsid").and_return(true)
          end

          it "stop iscsid.service" do
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
