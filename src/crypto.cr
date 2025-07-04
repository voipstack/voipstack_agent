require "openssl"
require "base64"
require "openssl_ext"

module Agent
  abstract class Crypto
    abstract def sign(msg : String) : String
    abstract def verify(msg : String, signature : String) : Bool
  end

  class DumbOpenSSL < Crypto
    def sign(msg : String) : String
      Base64.strict_encode(msg)
    end

    def verify(msg : String, signature : String) : Bool
      Base64.strict_encode(msg) == signature
    end
  end

  class NativeOpenSSL < Crypto
    def initialize(@private_key_pem_path : String)
    end

    def sign(msg : String) : String
      rsa = OpenSSL::PKey::RSA.new(File.read(@private_key_pem_path))
      digest = OpenSSL::Digest.new("sha256")
      signature = rsa.sign(digest, msg)

      Base64.strict_encode(signature)
    end

    def verify(msg : String, signature : String) : Bool
      raise "not supported"
    end
  end

  class NaiveOpenSSL < Crypto
    def initialize(@private_key_pem_path : String, @public_key_pem_path : String)
    end

    def sign(msg : String) : String
      stdin = IO::Memory.new(msg)
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      status = Process.run("openssl", ["dgst", "-sign", @private_key_pem_path, "-sha256"], output: stdout, error: stderr, input: stdin)
      unless status.success?
        raise "fails to generate signature: #{stderr.to_s}"
      end

      signature = Base64.strict_encode(stdout)
      signature
    end

    def verify(msg : String, signature : String) : Bool
      signature = Base64.decode(signature)
      stdin = IO::Memory.new(msg)
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      filetmp = File.tempfile("signature")
      filetmp.write(signature.to_slice)
      filetmp.flush

      status = Process.run("openssl", ["dgst", "-verify", @public_key_pem_path, "-sha256", "-signature", filetmp.path], output: stdout, error: stderr, input: stdin)

      stdout.to_s.includes?("Verified OK")
    end
  end
end
