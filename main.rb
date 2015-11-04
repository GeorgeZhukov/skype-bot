require 'rubygems'
require 'terminal-table'
require 'yaml'
require 'skype'
require 'slop'
require 'socket'

class Sender
  NOTIFY_MSG = "victim detected!"

  def initialize(port)
    @port = port
    @sock = UDPSocket.new()
    @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)

    ObjectSpace.define_finalizer(self, proc { @sock.close })

  end

  def notify()
    @sock.send(NOTIFY_MSG, 0, "<broadcast>", @port)
  end

end

class Receiver
  attr_accessor :callback

  def initialize(port)
    BasicSocket.do_not_reverse_lookup = true

    @port = port
    @sock = UDPSocket.new
    @sock.bind("0.0.0.0", @port)

    ObjectSpace.define_finalizer(self, proc { @sock.close })
  end

  def process()
    while true
      data, addr = @sock.recvfrom(1024)

      @callback.call(data)
    end
  end
end



# RubyGarage Skype Bot
class SkypeBot
  def initialize
    @config = YAML.load_file('config.yml')
    @opts = parse_opts()

    if @opts.sync?
      init_receiver()
      init_sender()

      puts 'Sync activated!'
    end

    Skype.config app_name: 'RubyGarageBot'
  end

  def run
    @chat = Skype.chats.find { |chat| chat.id.include? @config['token'] }

    return puts 'The chat does not found' unless @chat

    watcher
  end

  def list
    table = Terminal::Table.new
    table.title = 'Available Chats'
    table.headings = ['Chat Token', 'Topic', 'Members Count']

    Skype.chats.each do |chat|
      token = chat.id.match(%r{^(?<id>(.*))(;|\/)})[:id]
      table.add_row [token, chat.topic, chat.members.count]
    end

    puts table
    puts
  end

  private

  def parse_opts
    Slop.parse do |o|
      o.bool '-s', '--sync', 'synchronize bots over network'
    end
  end

  def init_sender
    @sender = Sender.new(@config["port"])
  end

  def init_receiver
    @receiver = Receiver.new(@config["port"])
    @receiver.callback = method(:sync)

    Thread.new { @receiver.process() }
  end

  # this methods called when someone broadcast
  # notify message over network
  def sync(data)
    send_message()
    @handled = true
  end

  def watcher
    last_message_id = 0

    loop do
      @chat.messages.last(25).each do |message|
        next unless last_message_id < message.id

        last_message_id = message.id

        process message
      end

      sleep @config['delay']
    end
  end

  def process(message)
    return @handled = false if @handled

    if valid?(message)
      @sender.notify() if @sender
      send_message()
    else
      print '.'
    end
  end

  def send_message
    @chat.post @config['message']
    print '*'
  end

  def valid?(message)
    message.user == @config['victim'] &&
      message.body.include?(@config['substring']) &&
      Time.now - message.time < @config['delay'] * 2
  end
end

begin
  bot = SkypeBot.new
  bot.list
  bot.run
rescue Interrupt
  puts "\n\nBye-bye! ¯\\_(ツ)_/¯\n\n"
end
