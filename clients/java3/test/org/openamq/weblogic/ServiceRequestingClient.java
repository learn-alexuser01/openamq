package org.openamq.weblogic;

import org.openamq.jms.*;
import org.apache.log4j.Logger;

import javax.naming.NamingException;
import javax.naming.InitialContext;
import javax.naming.Context;
import javax.jms.*;
import javax.jms.MessageConsumer;
import javax.jms.Session;
import java.util.Hashtable;
import java.io.File;
import java.io.FilenameFilter;
import java.io.Reader;
import java.io.FileReader;

/**
 * Created by IntelliJ IDEA.
 * User: U806869
 * Date: 28-May-2005
 * Time: 21:54:51
 * To change this template use File | Settings | File Templates.
 */
public class ServiceRequestingClient
{
    private static final Logger _log = Logger.getLogger(ServiceRequestingClient.class);
    private static final String JNDI_FACTORY = "weblogic.jndi.WLInitialContextFactory";
    private static final String JMS_FACTORY = "transientJMSConnectionFactory";

    private static class CallbackHandler implements MessageListener
    {
        private int _expectedMessageCount;

        private int _actualMessageCount;

        private long _startTime;

        private long _averageLatency;

        public CallbackHandler(int expectedMessageCount, long startTime)
        {
            _expectedMessageCount = expectedMessageCount;
            _startTime = startTime;
        }

        public void onMessage(Message m)
        {
            if (_log.isDebugEnabled())
            {
                _log.debug("Message received: " + m);
            }
            try
            {
                if (m.propertyExists("timeSent"))
                {
                    long timeSent = m.getLongProperty("timeSent");
                    long now = System.currentTimeMillis();
                    if (_averageLatency == 0)
                    {
                        _averageLatency = now - timeSent;
                        _log.info("Latency " + _averageLatency);
                    }
                    else
                    {
                        _log.info("Individual latency: " + (now-timeSent));
                        _averageLatency = (_averageLatency + (now - timeSent))/2;
                        _log.info("Average latency now: " + _averageLatency);
                    }
                }
            }
            catch (JMSException e)
            {
                _log.error("Could not calculate latency");
            }

            _actualMessageCount++;
            if (_actualMessageCount%1000 == 0)
            {
                try
                {
                    m.acknowledge();
                }
                catch (JMSException e)
                {
                    _log.error("Error acknowledging message");
                }
                _log.info("Received message count: " + _actualMessageCount);
            }
            /*if (!"henson".equals(m.toString()))
           {
               _log.error("Message response not correct: expected 'henson' but got " + m.toString());
           }
           else
           {
               if (_log.isDebugEnabled())
               {
                   _log.debug("Message " + m + " received");
               }
               else
               {
                   _log.info("Message received");
               }
           } */

            if (_actualMessageCount == _expectedMessageCount)
            {
                long timeTaken = System.currentTimeMillis() - _startTime;
                System.out.println("Total time taken to receive " + _expectedMessageCount+ " messages was " +
                                   timeTaken + "ms, equivalent to " +
                                   (_expectedMessageCount/(timeTaken/1000.0)) + " messages per second");
                System.out.println("Average latency is: " + _averageLatency);
            }
        }
    }

    public static void main(String[] args) throws Exception
    {
        if (args.length != 3)
        {
            System.out.println("Usage: IXPublisher <WLS URL> <sendQueue> <count> will publish count messages to ");
            System.out.println("queue sendQueue and waits for a response on a temp queue");
            System.exit(1);
        }

        String url = args[0];
        String sendQueue = args[1];
        int messageCount = Integer.parseInt(args[2]);

        InitialContext ctx = getInitialContext(url);

        QueueConnectionFactory qconFactory = (QueueConnectionFactory) ctx.lookup(JMS_FACTORY);
        QueueConnection qcon = qconFactory.createQueueConnection();
        QueueSession qsession = qcon.createQueueSession(false, Session.CLIENT_ACKNOWLEDGE);
        Queue sendQ = (Queue) ctx.lookup(sendQueue);
        Queue receiveQ = qsession.createTemporaryQueue();
        QueueSender qsender = qsession.createSender(sendQ);
        qsender.setDeliveryMode(DeliveryMode.NON_PERSISTENT);
        _log.debug("Queue sender created for service queue " + sendQ);

        javax.jms.MessageConsumer messageConsumer = (javax.jms.MessageConsumer) qsession.createConsumer(receiveQ);

        //TextMessage msg = _session.createTextMessage(tempDestination.getQueueName() + "/Presented to in conjunction with Mahnah Mahnah and the Snowths");
        final long startTime = System.currentTimeMillis();

        messageConsumer.setMessageListener(new CallbackHandler(messageCount, startTime));
        qcon.start();
        for (int i = 0; i < messageCount; i++)
        {
            TextMessage msg = qsession.createTextMessage("/Presented to in conjunction with Mahnah Mahnah and the Snowths:" + i);
            msg.setJMSReplyTo(receiveQ);
            if (i%1000 == 0)
            {
                long timeNow = System.currentTimeMillis();
                msg.setLongProperty("timeSent", timeNow);
            }
            qsender.send(msg);
        }

        new Thread("foo").start();
        //qsession.close();
        //qcon.close();
    }

    private static InitialContext getInitialContext(String url) throws NamingException
    {
        Hashtable env = new Hashtable();
        env.put(Context.INITIAL_CONTEXT_FACTORY, JNDI_FACTORY);
        env.put(Context.PROVIDER_URL, url);
        return new InitialContext(env);
    }
}