<?xml?>
<class
    name      = "amq_queue"
    comment   = "Queue class"
    version   = "1.0"
    copyright = "Copyright (c) 2004 JPMorgan"
    script    = "icl_gen"
    >
<doc>
Implements a queue object; held per virtual host and tracking the current
status of a queue destination. Acts as a container for queue consumers.
The queue object is backed by a persistent database table based on the
ipr_db_queue class.
</doc>

<inherit class = "ipr_hash_str" />
<inherit class = "ipr_db_queue" />
<option name = "nullify"  value = "1" />
<option name = "bigtable" value = "1" />

<data>
    <field name = "sender id"   type = "longint" >Original sender</field>
    <field name = "client id"   type = "longint" >Owned by this client</field>
    <field name = "header size" type = "longint" >Saved header size</field>
    <field name = "body size"   type = "longint" >Message body size</field>
    <field name = "priority"    type = "octet"   >Priority, 0-9</field>
    <field name = "expiration"  type = "longint" >Expiry date/time</field>
    <field name = "mime type"   type = "shortstr">Content MIME type</field>
    <field name = "encoding"    type = "shortstr">Content encoding</field>
    <field name = "identifier"  type = "shortstr">Message identifier</field>
    <field name = "headers"     type = "longstr" >Application headers</field>
    <field name = "content"     type = "longstr" >First body fragment</field>
    <field name = "spool size"  type = "longint" >Spooled size, or 0</field>
</data>

<import class = "ipr_classes"  />
<import class = "amq_db"       />
<import class = "amq_consumer" />
<import class = "amq_message"  />

<public name = "header">
#include "amq_core.h"
#include "amq_frames.h"
</public>

<private>
#include "amq_server_agent.h"
</private>

<context>
    /*  References to parent objects                                         */
    amq_vhost_t
        *vhost;                         /*  Parent virtual host              */

    /*  Object properties                                                    */
    amq_db_t
        *ddb;                           /*  Deprecated database handle       */
    amq_db_dest_t
        *dest;                          /*  Destination record               */
    amq_consumer_list_t
        *consumers;                     /*  Consumers for this queue         */
    amq_smessage_list_t
        *messages;                      /*  Non-pers. messages for queue     */
    qbyte
        window;                         /*  Total window availability        */
    qbyte
        last_id;                        /*  Last dispatched message          */
    size_t
        outstanding;                    /*  Nbr. outstanding messages        */
</context>

<method name = "new">
    <argument name = "vhost"     type = "amq_vhost_t *">Parent virtual host</argument>
    <argument name = "client_id" type = "qbyte"        >Owner, if any</argument>
    <argument name = "temporary" type = "Bool"         >Temporary queue?</argument>

    <!-- Remove these inherited arguments from the API -->
    <dismiss argument = "db"        value = "vhost->db"     />
    <dismiss argument = "filename"  value = "key"           />
    <dismiss argument = "table"     value = "vhost->queues" />

    /*  De-normalise from parent object, for simplicity of use               */
    self->vhost = vhost;
    self->db    = vhost->db;
    self->ddb   = vhost->ddb;

    /*  Initialise other properties                                          */
    self->dest      = amq_db_dest_new  ();
    self->consumers = amq_consumer_list_new ();
    self->messages  = amq_smessage_list_new ();

    self->dest->type = AMQP_SERVICE_QUEUE;
    ipr_shortstr_cpy (self->dest->name, key);

    /*  Fetch existing queue if caller specified a name                      */
    if (*key)
        amq_db_dest_fetch_byname (self->ddb, self->dest, AMQ_DB_FETCH_EQ);

    if (temporary) {
        /*  Create or attach to temporary queue                              */
        if (self->dest->id) {
            /*  Temporary queue exists, check client_id                      */
            ASSERT (client_id);
            if (self->dest->client_id == client_id)
                amq_queue_purge (self);
            else {
                coprintf ("$(selfname) E: temporary queue '%s' already in use", key);
                $(selfname)_destroy (&self);
            }
        }
        else {
            /*  Unnamed temporary queue - create it now                      */
            self->dest->temporary = TRUE;
            self->dest->client_id = client_id;
            amq_db_dest_insert (self->ddb, self->dest);
        }
    }
    else {
        /*  Create configured destination                                    */
        if (self->dest->id == 0)
            amq_db_dest_insert (self->ddb, self->dest);
    }
</method>

<method name = "destroy">
    amq_smessage_list_destroy (&self->messages);
    amq_consumer_list_destroy (&self->consumers);
    if (self->dest->temporary)
        amq_db_dest_delete (self->ddb, self->dest);
    amq_db_dest_destroy (&self->dest);
</method>

<method name = "consume" return = "queue">
    <argument name = "consumer" type = "amq_consumer_t *">Parent consumer</argument>
    <argument name = "suffix"   type = "char *"          >Destination name suffix</argument>
    <declare  name = "queue"    type = "$(selftype) *" default = "NULL"/>

    queue = $(selfname)_full_search (
        consumer->vhost->queues, consumer->handle->dest_name, suffix);
    if (queue) {
        if (queue->dest->client_id == consumer->client_id
        || !queue->dest->temporary) {
            amq_consumer_list_queue (queue->consumers, consumer);
            queue->window += consumer->window;
        }
        else {
            coprintf ("$(selfname) W: consume failed, not owner of temp.queue");
            queue = NULL;               /*  Not owner of temporary queue     */
        }
    }
</method>

<method name = "cancel" template = "function">
    <doc>
    Cancels a consumer on a specific queue, updating the queue as needed.
    </doc>
    <argument name = "consumer" type = "amq_consumer_t *">Parent consumer</argument>
    self->window -= consumer->window;
</method>

<method name = "dispatch" template = "function">
    <doc>
    Dispatches a specific message or all pending messages on a destination
    to all interested consumers.
    </doc>
    <argument name = "cur_message" type = "amq_smessage_t *">Message, if any</argument>
    <local>
    amq_smessage_t
        *message;
    amq_consumer_t
        *consumer;                      /*  Next consumer to process         */
    int
        finished;
    </local>

    /*  If we have a current message, save to disk or memory                 */
    if (cur_message) {
        if (self->outstanding > 0 || cur_message->persistent) {
            /*  Save to persistent storage                                   */
            self->outstanding++;
            amq_smessage_save    (cur_message, self);
            amq_smessage_destroy (&cur_message);
        }
        else
            /*  Added to memory queue                                        */
            amq_smessage_list_queue (self->messages, cur_message);
    }

    /*  Now process messages from memory or from disk                        */
    if (self->outstanding) {
        /*  Get oldest candidate message to dispatch                         */
        self->id = self->last_id;
        finished = amq_queue_fetch (self, IPR_QUEUE_GT);
        while (self->window && !finished) {
            if (self->client_id == 0) {
                consumer = s_get_next_consumer (self);
                message  = amq_smessage_new (consumer->handle);
                amq_smessage_load  (message, self);
                s_dispatch_message (consumer, message);

                /*  Update client id, using channel transaction if any       */
                self->client_id = consumer->client_id;
                amq_queue_update (self, consumer->channel->txn);
            }
            ASSERT (self->id > self->last_id);
            self->last_id = self->id;
            finished = amq_queue_fetch (self, IPR_QUEUE_NEXT);
        }
    }
    else {
        message = amq_smessage_list_first (self->messages);
        while (self->window && message) {
            consumer = s_get_next_consumer (self);
            amq_smessage_list_unlink (message);
            self->id = 0;               /*  Non-persistent message           */
            s_dispatch_message (consumer, message);
            message = amq_smessage_list_first (self->messages);
        }
    }
</method>

<private name = "header">
static amq_consumer_t *
s_get_next_consumer ($(selftype) *self);
static void
s_dispatch_message (amq_consumer_t *consumer, amq_smessage_t *message);
</private>

<private name = "footer">
static amq_consumer_t
*s_get_next_consumer ($(selftype) *self)
{
    amq_consumer_t
        *consumer;                      /*  Next consumer to process         */

    consumer = amq_consumer_list_first (self->consumers);
    while (consumer) {
        if (consumer->window && !consumer->handle->paused)
            break;
        consumer = amq_consumer_list_next (self->consumers, consumer);
    }
    return (consumer);
}

/*  Note that consumer->queue is also self at this stage                     */

static void
s_dispatch_message (
    amq_consumer_t *consumer,
    amq_smessage_t *message)
{
    amq_dispatch_t
        *dispatch;                      /*  Dispatched message queue entry   */

    ASSERT (consumer);
    dispatch = amq_dispatch_new (consumer, message);

    amq_server_agent_handle_notify (
        consumer->thread,
        (dbyte) consumer->handle->key,
        dispatch->message_nbr,
        FALSE, TRUE, FALSE,
        icl_mem_strdup (consumer->queue->dest->name),
        message,
        consumer->unreliable? dispatch: NULL);

    /*  Move consumer to end of list to round-robin it                       */
    amq_consumer_list_unlink (consumer);
    amq_consumer_list_queue  (consumer->queue->consumers, consumer);
}
</private>

<method name = "full search" return = "queue">
    <argument name = "queues" type = "$(selfname)_table_t *">Table to search</argument>
    <argument name = "prefix" type = "char *"               >Queue prefix</argument>
    <argument name = "suffix" type = "char *"               >Queue suffix</argument>
    <declare  name = "queue"  type = "$(selftype) *" default = "NULL"/>
    <doc>
    Handles queue name hierarchies, whereby the queue name is built
    from a prefix specified at handle-open time, and a suffix specified
    at the individual command level.
    </doc>
    <local>
    ipr_shortstr_t
        fullname;
    </local>
    ipr_shortstr_fmt (fullname, "%s%s", prefix, suffix);
    queue = amq_queue_search (queues, fullname);
</method>

<method name = "selftest" />

</class>
