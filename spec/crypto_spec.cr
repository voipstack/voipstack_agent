require "./spec_helper"

describe Agent::Crypto do
  it "Naive sign" do
    private_key_pem_path = File.tempname(".pem")
    public_key_pem_path = File.tempname(".pem")

    %x[openssl genrsa -out #{private_key_pem_path} 2048]
    $?.exit_code.should eq(0)
    %x[openssl rsa -pubout -in #{private_key_pem_path} -out #{public_key_pem_path}]
    $?.exit_code.should eq(0)

    crypto = Agent::NaiveOpenSSL.new(private_key_pem_path, public_key_pem_path)
    signature = crypto.sign("test")
    crypto.verify("teastaa", signature).should eq(false)
    crypto.verify("test", signature).should eq(true)
  end

  it "Naitive sign" do
    private_key_pem_path = File.tempname(".pem")
    public_key_pem_path = File.tempname(".pem")

    %x[openssl genrsa -out #{private_key_pem_path} 2048]
    $?.exit_code.should eq(0)
    %x[openssl rsa -pubout -in #{private_key_pem_path} -out #{public_key_pem_path}]
    $?.exit_code.should eq(0)

    crypto = Agent::NativeOpenSSL.new(private_key_pem_path)
    naive_crypto = Agent::NaiveOpenSSL.new(private_key_pem_path, public_key_pem_path)
    signature = crypto.sign("test")
    naive_crypto.verify("teastaa", signature).should eq(false)
    naive_crypto.verify("test", signature).should eq(true)
  end
end
