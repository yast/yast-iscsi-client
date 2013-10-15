require_relative '../src/modules/IscsiClientLib'

describe Yast::IscsiClientLibClass do

  before :each do
    @iscsilib = Yast::IscsiClientLibClass.new
    @iscsilib.main() 
  end

  describe "#ipEqual" do
    context "with IPv4 arguments not matching" do
      it "returns false" do
        expect(@iscsilib.ipEqual?("213:23:", "...")).to be_false
      end
    end
    context "with equal IPv4 addresses (without port)" do
      it "returns true" do
        expect(@iscsilib.ipEqual?("10.10.10.1", "10.10.10.1")).to be_true
      end
    end
    context "with equal IPv4 addresses and equal port" do
      it "returns true" do
        expect(@iscsilib.ipEqual?("10.10.10.1:345", "10.10.10.1:345")).to be_true
      end
    end
    context "with equal IPv4 addresses and different ports" do
      it "returns false" do
        expect(@iscsilib.ipEqual?("10.10.10.1:345", "10.10.10.1:500")).to be_false
      end
    end
    context "with invalid IPv6 arguments" do
      it "returns false" do
        expect(@iscsilib.ipEqual?("[213:23:]", "...")).to be_false
      end
    end
    context "with equal (but different string) and valid IPv6 arguments (without port)" do
      it "returns true" do
        expect(@iscsilib.ipEqual?("[2620:0113:1c0:8080:4ec:544a:000d:3d62]",
                                  "[2620:113:1c0:8080:4ec:544a:d:3d62]")).to be_true
      end
    end
    context "with equal (same string) and valid IPv6 arguments (without port)" do
      it "returns true" do
        expect(@iscsilib.ipEqual?("[2620:113:1c0:8080:4ec:544a:000d:3d62]",
                                  "[2620:113:1c0:8080:4ec:544a:d:3d62]")).to be_true
      end
    end
    context "with equal (but different string) and valid IPv6 arguments and equal ports" do
      it "returns true" do
        expect(@iscsilib.ipEqual?("[0020:0113:80c0:8080:0:544a:3b9d:3d62]:456",
                                  "[20:113:80c0:8080::544a:3b9d:3d62]:456")).to be_true
      end
    end
    context "with equal (but different string) IPv6 arguments and different ports" do
      it "returns false" do
        expect(@iscsilib.ipEqual?("[2620:0113:80c0:8080:54ec:004a:3b9d:3d62]:456",
                                  "[2620:113:80c0:8080:54ec:4a:3b9d:3d62]:4")).to be_false
      end
    end
    context "with equal (same string) IPv6 arguments and different ports" do
      it "returns false" do
        expect(@iscsilib.ipEqual?("[2620:113:80c0:8080:54ec:544a:3b9d:3d62]:456",
                                  "[2620:113:80c0:8080:54ec:544a:3b9d:3d62]:4")).to be_false
      end
    end
  end
end
