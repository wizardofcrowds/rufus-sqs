
#
# testing the sqs with yaml messages
#

require 'test/unit'

require 'yaml'
require 'base64'
require 'digest/md5'

require 'rufus/sqs'


class SqsTest < Test::Unit::TestCase

    #def setup
    #end

    #def teardown
    #end

    def test_usage

        qs = Rufus::SQS::QueueService.new

        queue_name = Digest::MD5.hexdigest(rand.to_s + Time.now.to_s)[0..20]

        qs.create_queue queue_name

        msg = "hello SQS world !"

        msg_id = qs.put_message queue_name, msg

        sleep 1

        msgs = qs.get_messages queue_name

        assert_equal 1, msgs.size
        assert_equal msg, msgs[0].message_body

        qs.delete_queue queue_name
    end

    def test_0

        hash = {
            :red => :color,
            :count => "twelve",
            "fish" => "sakana",
            :llen => 4,
            :list => [ 0, 1, 2, 3, 4, :fizz ]
        }

        qs = Rufus::SQS::QueueService.new

        queue_name = Digest::MD5.hexdigest(rand.to_s + Time.now.to_s)[0..20]

        qs.create_queue(queue_name)

        puts "created queue #{queue_name}"

        queue = qs.get_queue_attributes(queue_name)
        assert_equal 0, queue.approximate_number_of_messages

        msg = YAML.dump(hash)
        msg = Base64.encode64(msg)

        puts "message size is #{msg.size.to_f / 1024.0} K"

        qs.send_message(queue_name, msg)

        puts "sent hash as message"

        sleep 1

        msgs = qs.get_messages(queue_name)

        puts "got messages back"
        
        msg = Base64.decode64(msgs[0].message_body)
        msg = YAML.load(msg)

        pp msg

        assert_equal msg, hash

        qs.delete_message(queue_name, msgs[0].receipt_handle)

        puts "deleted the message from queue #{queue_name}"

        sleep 1

        assert_equal 0, qs.get_messages(queue_name).size

        qs.delete_queue(queue_name)
    end
end

