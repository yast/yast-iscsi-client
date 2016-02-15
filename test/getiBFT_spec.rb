#!/usr/bin/env rspec
require_relative '../src/modules/IscsiClientLib'

describe Yast::IscsiClientLibClass do

  before :each do
    @iscsilib = Yast::IscsiClientLibClass.new
    @iscsilib.main() 
  end

  describe "#getiBFT" do
    context "when filtering output of 'iscsiadm -m fw'" do
      it "returns data in form of a map " do
        allow(Yast::Arch).to receive(:architecture).and_return("x86_64")
        allow(@iscsilib).to receive(:getFirmwareInfo).
          and_return("# BEGIN RECORD 2.0-872\n"\
                     "iface.bootproto = STATIC\n"\
                     "iface.transport_name = tcp\n"\
                     "iface.hwaddress = 00:00:c9:b1:bc:7f\n"\
                     "iface.initiatorname = iqn.2011-05.com.emulex:eraptorrfshoneport1\n"\
                     "iface.ipaddress = 2620:0113:80c0:8000:000c:0000:0000:04dc\n"\
                     "node.conn[0].address = 172.0.21.6\n"\
                     "node.conn[0].port = 3260\n"\
                     "node.name = iqn.1986-03.com.ibm:sn.135061874\n"\
                     "# END RECORD\n"
                     )

        ibft_data = @iscsilib.getiBFT()

        expect(ibft_data).to eq(
                                {"# BEGIN RECORD 2.0-872" => "", 
                                  "# END RECORD" => "", 
                                  "iface.bootproto" => "STATIC", 
                                  "iface.hwaddress" => "00:00:c9:b1:bc:7f", 
                                  "iface.initiatorname" => "iqn.2011-05.com.emulex:eraptorrfshoneport1", 
                                  "iface.transport_name" => "tcp",
                                  "iface.ipaddress" => "2620:0113:80c0:8000:000c:0000:0000:04dc",
                                  "node.conn[0].address" => "172.0.21.6", 
                                  "node.conn[0].port" => "3260", 
                                  "node.name" => "iqn.1986-03.com.ibm:sn.135061874"})
      end
    end

    context "when could not get list of targets from firmware" do
      it "returns an empty map " do
        allow(Yast::Arch).to receive(:architecture).and_return("x86_64")
        allow(@iscsilib).to receive(:getFirmwareInfo).and_return("")

        ibft_data = @iscsilib.getiBFT()
         
        expect(ibft_data).to eq({})
      end
    end

    context "when not on x86 hardware" do
      it "returns an empty map " do
        allow(Yast::Arch).to receive(:architecture).and_return("s390_64")
        
        ibft_data = @iscsilib.getiBFT()

        expect(ibft_data).to eq({})
      end
    end

 end
end
