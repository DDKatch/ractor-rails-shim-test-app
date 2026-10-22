# frozen_string_literal: true

# RAILS_FEATURES.md #128: an app-defined ENCRYPTED storage service — a
# custom ActiveStorage::Service subclass (DiskService base) that encrypts
# at rest with AES-256-GCM. File layout on disk:
#   [12-byte IV][16-byte auth tag][ciphertext]
# The key is derived per call (NO ivar memo — the service instance is
# deep-frozen in the app's shared graph, so a lazy memo write would
# FrozenError in workers) from the application's secret_key_base.
#
# Lives under lib/active_storage/service/ (NOT an autoload dir) because the
# service Configurator does `require "active_storage/service/encrypted_disk_service"`
# — resolvable only via the load path; config/initializers/encrypted_storage.rb
# requires it at boot so worker-side requires no-op (already loaded).
require "openssl"

module ActiveStorage
  class Service::EncryptedDiskService < Service::DiskService
    IV_BYTES = 12
    TAG_BYTES = 16

    # Expose the root for probe diagnostics (DiskService keeps @root private).
    def root
      @root
    end

    def upload(key, io, checksum: nil, filename: nil, content_type: nil,
               disposition: nil, custom_metadata: {})
      instrument :upload, key: key do
        encrypt_and_write(key, io.read)
      end
    end

    def download(key)
      instrument :download, key: key do
        decrypt_file(key)
      end
    end

    def download_chunk(key, range)
      instrument :download_chunk, key: key, range: range do
        decrypt_file(key).byteslice(range)
      end
    end

    private
      def encrypt_and_write(key, plaintext)
        cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
        cipher.key = encryption_key
        iv = cipher.random_iv
        ciphertext = cipher.update(plaintext) + cipher.final
        tag = cipher.auth_tag
        File.open(make_path_for(key), "wb") do |file|
          file.write(iv)
          file.write(tag)
          file.write(ciphertext)
        end
      end

      def decrypt_file(key)
        raw = File.binread(path_for(key))
        iv = raw.byteslice(0, IV_BYTES)
        tag = raw.byteslice(IV_BYTES, TAG_BYTES)
        ciphertext = raw.byteslice(IV_BYTES + TAG_BYTES, raw.bytesize - IV_BYTES - TAG_BYTES)
        cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
        cipher.key = encryption_key
        cipher.iv = iv
        cipher.auth_tag = tag
        cipher.auth_data = ""
        cipher.update(ciphertext) + cipher.final
      end

      # Deterministic across processes and Ractors — the same key must
      # encrypt AND decrypt (a per-call random token would never decrypt).
      def encryption_key
        OpenSSL::Digest::SHA256.digest(secret_salt)
      end

      def secret_salt
        base = Rails.application.secret_key_base
        raise "secret_key_base required for EncryptedDiskService" if base.blank?
        "active-storage-encrypted-disk:#{base}"
      end
  end
end
