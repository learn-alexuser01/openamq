<?xml?>
<class
    name      = "amq_broker"
    comment   = "AMQ server broker class"
    version   = "1.0"
    script    = "smt_object_gen"
    target    = "smt"
    >
<inherit class = "asl_broker" />
<inherit class = "amq_console_object" />
<option name = "basename" value = "amq_server" />

<!-- Console definitions for this object -->
<data name = "cml">
    <class name = "broker" label = "Broker">
        <field name = "name" label = "Broker name">
          <get>icl_shortstr_fmt (field_value, "OpenAMQ %s", VERSION);</get>
        </field>
        <field name = "started" label = "Date, time broker started">
          <get>ipr_time_iso8601 (self->started,
            ipr_date_format_minute, 0, ipr_time_zone (), field_value);</get>
        </field>
        <field name = "messages_in" type = "int" label = "Messages published">
          <rule name = "show on summary" />
          <get>icl_shortstr_fmt (field_value, "%d", self->contents_in);</get>
        </field>
        <field name = "messages_out" type = "int" label = "Messages consumed">
          <rule name = "show on summary" />
          <get>icl_shortstr_fmt (field_value, "%d", self->contents_out);</get>
        </field>
        <field name = "megabytes_in" type = "int" label = "Megabytes published">
          <rule name = "show on summary" />
          <get>icl_shortstr_fmt (field_value, "%d", (int) (self->traffic_in / (1024 * 1024)));</get>
        </field>
        <field name = "megabytes_out" type = "int" label = "Megabytes consumed">
          <rule name = "show on summary" />
          <get>icl_shortstr_fmt (field_value, "%d", (int) (self->traffic_out / (1024 * 1024)));</get>
        </field>
        <field name = "locked" type = "bool" label = "Broker is locked?">
          <get>icl_shortstr_fmt (field_value, "%d", self->locked);</get>
        </field>
        <field name = "datamem" label = "Memory used for all data">
          <get>icl_shortstr_fmt (field_value, "%dK", (int) (icl_mem_used () / 1024));</get>
        </field>
        <field name = "bucketmem" label = "Memory used for messages">
          <get>icl_shortstr_fmt (field_value, "%dK", (int) (ipr_bucket_used () / 1024));</get>
        </field>
        <field name = "messages" type = "int" label = "Number of queued messages">
          <get>icl_shortstr_fmt (field_value, "%d", amq_content_basic_count ());</get>
        </field>
        <field name = "consumers" type = "int" label = "Number of queue consumers">
          <get>icl_shortstr_fmt (field_value, "%d", amq_consumer_count ());</get>
        </field>
        <field name = "bindings" type = "int" label = "Number of queue bindings">
          <get>icl_shortstr_fmt (field_value, "%d", amq_binding_count ());</get>
        </field>

        <class name = "exchange" label = "Message exchanges" repeat = "1">
          <local>
            amq_exchange_t
                *exchange;
          </local>
          <get>
            exchange = amq_exchange_by_vhost_first (self->vhost->exchange_list);
            icl_shortstr_fmt (field_value, "%d", exchange->object_id);
          </get>
          <next>
            exchange = amq_exchange_by_vhost_next (&exchange);
            if (exchange)
                icl_shortstr_fmt (field_value, "%d", exchange->object_id);
          </next>
        </class>

        <class name = "queue" label = "Shared queues" repeat = "1">
          <rule name = "monitor top" field = "pending" />
          <local>
            amq_queue_t
                *queue;
          </local>
          <get>
            //  Get first queue and then skip private queues
            queue = amq_queue_by_vhost_first (self->vhost->queue_list);
            while (queue && queue->exclusive)
                queue = amq_queue_by_vhost_next (&queue);
            if (queue)
                icl_shortstr_fmt (field_value, "%d", queue->object_id);
          </get>
          <next>
            //  Get next queue and then skip private queues
            queue = amq_queue_by_vhost_next (&queue);
            while (queue && queue->exclusive)
                queue = amq_queue_by_vhost_next (&queue);
            if (queue)
                icl_shortstr_fmt (field_value, "%d", queue->object_id);
          </next>
        </class>

        <class name = "connection" label = "Connections" repeat = "1">
          <rule name = "monitor top" field = "pending" />
          <local>
            amq_connection_t
                *connection;
          </local>
          <get>
            connection = amq_connection_by_broker_first (self->mgt_connection_list);
            if (connection)
                icl_shortstr_fmt (field_value, "%d", connection->object_id);
          </get>
          <next>
            connection = amq_connection_by_broker_next (&connection);
            if (connection)
                icl_shortstr_fmt (field_value, "%d", connection->object_id);
          </next>
        </class>

        <class name = "cluster" label = "Cluster">
          <get>
            icl_shortstr_fmt (field_value, "%d", amq_cluster->object_id);
          </get>
        </class>

        <class name = "config" label = "Configuration" source = "amq_console_config">
          <get>
            icl_shortstr_fmt (field_value, "%d", amq_console_config->object_id);
          </get>
        </class>

        <method name = "shutdown" label = "Shutdown broker">
          <doc>
          Shuts-down the broker. All client connections are broken, and the
          broker process will exit.
          </doc>
          <exec>
            smt_log_print (amq_broker->alert_log,
                "W: operator requested shutdown - closing all connections");
            smt_shut_down ();
          </exec>
        </method>

        <!-- Not working yet
        <method name = "restart" label = "Restart broker">
          <doc>
          Restarts the broker. All client connections are broken, and the
          broker process will then restart.
          </doc>
          <exec>
            smt_log_print (amq_broker->alert_log,
                "W: operator requested restart - closing all connections");
            self->restart = TRUE;       //  Tell main line to restart
            smt_shut_down ();
          </exec>
        </method>
        -->

        <method name = "lock" label = "Prevent new connections">
          <doc>
          Locks or unlocks the broker. When the broker is locked it will refuse
          new client connections, though you can still connect using the shell.
          </doc>
          <field name = "setting" type = "bool" label = "1|0"/>
          <exec>self->locked = setting;</exec>
        </method>

        <method name = "shake" label = "Shake broker memory">
          <doc>
          Shakes the broker, which forces it to do a garbage collection. The
          method may create delays for message processing; do not use during
          heavy traffic.
          </doc>
          <exec>icl_system_purge ();</exec>
        </method>
    </class>
</data>

<private name = "async header">
#include "version.h"
</private>

<context>
    Bool
        locked,                         //  Is broker locked?
        master,                         //  Acting as cluster master server?
        restart;                        //  Restart broker after exit?
    int
        dump_state_timer,               //  Dump state timer
        auto_crash_timer,               //  Automatic failure
        auto_block_timer;               //  Automatic blockage
    amq_vhost_t
        *vhost;                         //  Single vhost (for now)
    amq_connection_by_broker_t
        *mgt_connection_list;           //  Connection mgt objects list
</context>

<method name = "new">
    //
    //  We use a single global vhost for now
    //  TODO: load list of vhosts from config file
    self->vhost = amq_vhost_new (self, "/");
    self->dump_state_timer = amq_server_config_dump_state (amq_server_config);
    self->auto_crash_timer = amq_server_config_auto_crash (amq_server_config);
    self->auto_block_timer = amq_server_config_auto_block (amq_server_config);
    self->mgt_connection_list = amq_connection_by_broker_new ();
    amq_console_config = amq_console_config_new (self);

    randomize ();
    if (self->auto_crash_timer)
        self->auto_crash_timer = randomof (self->auto_crash_timer) + 1;
    if (self->auto_block_timer)
        self->auto_block_timer = randomof (self->auto_block_timer) + 1;
</method>

<method name = "destroy">
    <action>
    amq_console_config_destroy (&amq_console_config);
    amq_vhost_destroy (&self->vhost);
    amq_connection_by_broker_destroy (&self->mgt_connection_list);
    </action>
</method>

<method name = "unbind queue" template = "async function" async = "1">
    <doc>
    Unbind a queue from the broker.
    </doc>
    <argument name = "queue" type = "amq_queue_t *">The queue to unbind</argument>
    //
    <possess>
    queue = amq_queue_link (queue);
    </possess>
    <release>
    amq_queue_unlink (&queue);
    </release>
    //
    <action>
    amq_server_connection_t
        *connection;

    //  Go through all connections
    connection = amq_server_connection_list_first (self->connection_list);
    while (connection) {
        amq_server_connection_unbind_queue (connection, queue);
        connection = amq_server_connection_list_next (&connection);
    }
    </action>
</method>

<event name = "monitor">
    <action>
    //  Config may change, in which case use new configured values
    /*
    -- TODO:
    -- if config is zero, stop timer
    -- if timer is zero, take from config
    if (self->monitor_timer == 0)
        self->monitor_timer = amq_server_config_monitor (amq_server_config);
    if (self->dump_state_timer == 0)
        self->dump_state_timer = amq_server_config_dump_state (amq_server_config);
    if (self->auto_crash_timer == 0)
        self->auto_crash_timer = amq_server_config_auto_crash (amq_server_config);
    if (self->auto_crash_timer == 0)
        self->auto_block_timer = amq_server_config_auto_block (amq_server_config);
    */
    if (self->dump_state_timer) {
        self->dump_state_timer--;
        if (self->dump_state_timer == 0) {
            self->dump_state_timer = amq_server_config_dump_state (amq_server_config);
            smt_log_print (amq_broker->alert_log,
                "I: cnn=%d msg=%d mem=%uK/%uK exc=%d que=%d csm=%d bnd=%d adx=%d idx=%d map=%d",
                amq_server_connection_count (),
                amq_content_basic_count (),
                ipr_bucket_used () / 1024,
                icl_mem_used () / 1024,
                amq_exchange_count (),
                amq_queue_count (),
                amq_consumer_count (),
                amq_binding_count (),
                amq_index_count (),
                ipr_index_count (),
                ipr_bits_count ());
        }
    }
    if (self->auto_crash_timer) {
        if (--self->auto_crash_timer == 0) {
            smt_log_print (amq_broker->alert_log,
                "W: ************************  AUTO-CRASH  ************************");
            smt_log_print (amq_broker->alert_log,
                "W: server is now emulating a system crash, and will exit brutally.");
            exit (0);
        }
    }
    if (self->auto_block_timer) {
        if (--self->auto_block_timer == 0) {
            smt_log_print (amq_broker->alert_log,
                "W: ************************  AUTO-BLOCK  ************************");
            smt_log_print (amq_broker->alert_log,
                "W: server is now emulating a blockage, and will freeze for 5 minutes.");
            sleep (300);
        }
    }
    </action>
</event>

<method name = "selftest" />

</class>