# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"

require "dependabot/rust_toolchain/file_parser/toolchain_channel_parser"

module Dependabot
  module RustToolchain
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_files.each do |dependency_file|
          dependency = parse_dependency_file(dependency_file)
          next unless dependency

          dependency_set << dependency
        end

        dependency_set.dependencies
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No dependency files!"
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::Dependency)) }
      def parse_dependency_file(dependency_file)
        content = T.must(dependency_file.content).strip

        raw_channel = case dependency_file.name
                      when /\.toml$/
                        parse_toml_toolchain(content)
                      else
                        parse_plaintext_toolchain(content)
                      end

        return if raw_channel.nil?

        toolchain_channel = parse_toolchain_channel(raw_channel)
        return if toolchain_channel.nil?

        Dependency.new(
          name: "rust-toolchain",
          version: raw_channel,
          requirements: [],
          package_manager: "rust_toolchain",
          metadata: {
            toolchain_channel: toolchain_channel
          }
        )
      end

      sig { params(content: String).returns(String) }
      def parse_toml_toolchain(content)
        parsed = TomlRB.parse(content)

        channel = parsed.dig("toolchain", "channel")
        return channel if channel

        Dependabot.logger.warn("No toolchain section found in rust-toolchain.toml file.")
        raise Dependabot::DependencyFileNotParseable, "rust-toolchain.toml"
      rescue TomlRB::ParseError => e
        Dependabot.logger.warn("Failed to parse rust-toolchain.toml file: #{e.message}")
        raise Dependabot::DependencyFileNotParseable, "rust-toolchain.toml"
      end

      sig { params(content: String).returns(String) }
      def parse_plaintext_toolchain(content) = content.strip

      sig { params(raw_toolchain_channel: String).returns(T.nilable(T::Hash[Symbol, T.nilable(String)])) }
      def parse_toolchain_channel(raw_toolchain_channel)
        ToolchainChannelParser.new(
          raw_toolchain_channel
        ).parse
      end
    end
  end
end

Dependabot::FileParsers.register("rust_toolchain", Dependabot::RustToolchain::FileParser)
