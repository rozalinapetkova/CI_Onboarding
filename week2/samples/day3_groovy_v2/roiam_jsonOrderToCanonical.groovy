/*
 * Day 2.3 reference script — JSON branch of the Order Translator.
 * Place at: script/v2/roiam_jsonOrderToCanonical.groovy
 *
 * Reads a JSON order body, emits the canonical XML the XSLT enrichment step expects.
 * Demonstrates the project conventions: streaming Reader, JsonSlurper.parse(reader),
 * MessageLog with null-guard, helper method (not a class), explicit types on locals.
 */
import com.sap.it.script.v2.api.Message;
import java.io.Reader;
import java.io.StringWriter;
import groovy.json.JsonSlurper;
import groovy.xml.MarkupBuilder;

def Message processData(Message message) {
    Reader reader = message.getBody(java.io.Reader);
    def order = new JsonSlurper().parse(reader);

    String orderId  = order.orderId  as String;
    String customer = order.customer as String;
    String currency = (order.currency as String)?.toUpperCase();
    Number total    = (order.totalAmount ?: 0) as Number;
    List lines      = (order.lines ?: []) as List;

    String priority = priorityFromAmount(total);

    StringWriter sw = new StringWriter();
    MarkupBuilder xml = new MarkupBuilder(sw);
    xml.CanonicalOrder {
        header {
            'orderId'(orderId);
            'customer'(customer);
            'currencyIso4217'(currency);
            'totalAmount'(total);
            'priority'(priority);
        }
        'lines' {
            lines.each { line ->
                'line' {
                    'sku'(line.sku as String);
                    'quantity'((line.quantity ?: 0) as Number);
                    'lineTotal'(((line.quantity ?: 0) as BigDecimal) *
                                ((line.unitPrice ?: 0) as BigDecimal));
                }
            }
        }
        'totals' {
            'lineCount'(lines.size());
            'grandTotal'(total);
        }
    }

    def messageLog = messageLogFactory?.createMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("orderId", orderId ?: "");
        messageLog.addAttachmentAsString("canonical-from-json.xml",
            sw.toString(), "application/xml");
    }

    message.setHeader("X-Order-Id", orderId);
    message.setBody(sw.toString());
    return message;
}

String priorityFromAmount(Number total) {
    BigDecimal n = total as BigDecimal;
    if (n >= 100000g) return "HIGH";
    if (n >= 10000g)  return "MEDIUM";
    return "LOW";
}
