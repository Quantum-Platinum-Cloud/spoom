# typed: strict
# frozen_string_literal: true

module Spoom
  class Context
    # Sorbet features for a context
    module Sorbet
      extend T::Sig
      extend T::Helpers

      requires_ancestor { Context }

      # Run `bundle exec srb` in this context directory
      sig { params(arg: String, sorbet_bin: T.nilable(String), capture_err: T::Boolean).returns(ExecResult) }
      def srb(*arg, sorbet_bin: nil, capture_err: true)
        res = if sorbet_bin
          exec("#{sorbet_bin} #{arg.join(" ")}", capture_err: capture_err)
        else
          bundle_exec("srb #{arg.join(" ")}", capture_err: capture_err)
        end

        case res.exit_code
        when Spoom::Sorbet::KILLED_CODE
          raise Spoom::Sorbet::Error::Killed.new("Sorbet was killed.", res)
        when Spoom::Sorbet::SEGFAULT_CODE
          raise Spoom::Sorbet::Error::Segfault.new("Sorbet segfaulted.", res)
        end

        res
      end

      sig { params(arg: String, sorbet_bin: T.nilable(String), capture_err: T::Boolean).returns(ExecResult) }
      def srb_tc(*arg, sorbet_bin: nil, capture_err: true)
        arg.prepend("tc") unless sorbet_bin
        T.unsafe(self).srb(*arg, sorbet_bin: sorbet_bin, capture_err: capture_err)
      end

      sig do
        params(
          arg: String,
          sorbet_bin: T.nilable(String),
          capture_err: T::Boolean,
        ).returns(T.nilable(T::Hash[String, Integer]))
      end
      def srb_metrics(*arg, sorbet_bin: nil, capture_err: false)
        metrics_file = "metrics.tmp"

        T.unsafe(self).srb_tc(
          "--metrics-file",
          metrics_file,
          *arg,
          sorbet_bin: sorbet_bin,
          capture_err: capture_err,
        )
        return nil unless file?(metrics_file)

        metrics_path = absolute_path_to(metrics_file)
        metrics = Spoom::Sorbet::MetricsParser.parse_file(metrics_path)
        remove!(metrics_file)
        metrics
      end

      # List all files typechecked by Sorbet from its `config`
      sig { params(with_config: T.nilable(Spoom::Sorbet::Config)).returns(T::Array[String]) }
      def srb_files(with_config: nil)
        config = with_config || sorbet_config
        regs = config.ignore.map { |string| Regexp.new(Regexp.escape(string)) }
        exts = config.allowed_extensions.empty? ? [".rb", ".rbi"] : config.allowed_extensions
        glob("**/*{#{exts.join(",")}}").reject do |f|
          regs.any? { |re| re.match?(f) }
        end.sort
      end

      sig { params(arg: String, sorbet_bin: T.nilable(String), capture_err: T::Boolean).returns(T.nilable(String)) }
      def srb_version(*arg, sorbet_bin: nil, capture_err: true)
        res = T.unsafe(self).srb_tc("--no-config", "--version", *arg, sorbet_bin: sorbet_bin, capture_err: capture_err)
        return nil unless res.status

        res.out.split(" ")[2]
      end

      # Does this context has a `sorbet/config` file?
      sig { returns(T::Boolean) }
      def has_sorbet_config?
        file?(Spoom::Sorbet::CONFIG_PATH)
      end

      sig { returns(Spoom::Sorbet::Config) }
      def sorbet_config
        Spoom::Sorbet::Config.parse_string(read_sorbet_config)
      end

      # Read the contents of `sorbet/config` in this context directory
      sig { returns(String) }
      def read_sorbet_config
        read(Spoom::Sorbet::CONFIG_PATH)
      end

      # Set the `contents` of `sorbet/config` in this context directory
      sig { params(contents: String, append: T::Boolean).void }
      def write_sorbet_config!(contents, append: false)
        write!(Spoom::Sorbet::CONFIG_PATH, contents, append: append)
      end

      # Read the strictness sigil from the file at `relative_path` (returns `nil` if no sigil)
      sig { params(relative_path: String).returns(T.nilable(String)) }
      def read_file_strictness(relative_path)
        Spoom::Sorbet::Sigils.file_strictness(absolute_path_to(relative_path))
      end

      # Get the commit introducing the `sorbet/config` file
      sig { returns(T.nilable(Spoom::Git::Commit)) }
      def sorbet_intro_commit
        res = git_log("--diff-filter=A --format='%h %at' -1 -- sorbet/config")
        return nil unless res.status

        out = res.out.strip
        return nil if out.empty?

        Spoom::Git::Commit.parse_line(out)
      end

      # Get the commit removing the `sorbet/config` file
      sig { returns(T.nilable(Spoom::Git::Commit)) }
      def sorbet_removal_commit
        res = git_log("--diff-filter=D --format='%h %at' -1 -- sorbet/config")
        return nil unless res.status

        out = res.out.strip
        return nil if out.empty?

        Spoom::Git::Commit.parse_line(out)
      end
    end
  end
end
