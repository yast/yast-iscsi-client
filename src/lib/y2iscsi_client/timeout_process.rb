require "yast"
require "yast2/execute"

Yast.import "Popup"

module Y2IscsiClient
  module TimeoutProcess
    include Yast::I18n
    extend Yast::I18n

    # @param [Array<String>] command as list of arguments
    # @param [Integer] timeout in seconds
    # @return [Array<Boolean, Array<String>] return pair of boolean if command
    #   succeed and stdout lines without ending newline
    def self.run(command, timeout: 10)
      textdomain "iscsi-client"

      # pass kill-after to ensure that command really dies even if ignore TERM
      stdout, stderr, exit_status = Yast::Execute.on_target!(
        "/usr/bin/timeout", "--kill-after", "5s", "#{timeout}s",
        *command, stdout: :capture, stderr: :capture,
        allowed_exitstatus: 0..255, env: { "LC_ALL" => "POSIX" }
      )

      output = stdout.split("\n")
      case(exit_status)
      when 0 then [true, output]
      when 124, ( 128 + 9 )
        Yast::Popup.Error(_("Command timed out"))
        [false, output]
      else
        Yast::Popup.Error(stderr)
        [false, output]
      end
    end
  end
end
