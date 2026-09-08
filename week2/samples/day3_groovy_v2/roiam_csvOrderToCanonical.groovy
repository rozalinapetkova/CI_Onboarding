/*
 * Day 2.3 reference script — CSV branch of the Order Translator.
 * Place at: script/v2/roiam_csvOrderToCanonical.groovy
 *
 * CSV body columns: sku,quantity,unitPrice (header line required).
 * Order header (orderId, customer, currency) comes from request headers.
 * Throws RuntimeException when required input is missing — by design.
 */
import com.sap.it.script.v2.api.Message;
import java.io.Reader;
import java.io.BufferedReader;
import java.io.StringWriter;
import groovy.xml.MarkupBuilder;

def Message processData(Message message) {
    def headers = message.getHeaders();
    String orderId  = headers.get("X-Order-Id")  as String;
    String customer = headers.get("X-Customer")  as String;
    String currency = (headers.get("X-Currency") as String)?.toUpperCase();
    if (orderId == null || customer == null || currency == null) {
        throw new RuntimeException(
            "CSV branch requires X-Order-Id, X-Customer, X-Currency headers");
    }

    BufferedReader reader = new BufferedReader(message.getBody(java.io.Reader));
    String hdr = reader.readLine();
    if (hdr == null) throw new RuntimeException("Empty CSV body");

    List<String> cols = hdr.split(",").collect { it.trim() };
    int iSku   = cols.indexOf("sku");
    int iQty   = cols.indexOf("quantity");
    int iPrice = cols.indexOf("unitPrice");
    if (iSku < 0 || iQty < 0 || iPrice < 0) {
        throw new RuntimeException("CSV header must contain sku,quantity,unitPrice");
    }

    List<Map> lines = new ArrayList<>();
    BigDecimal grand = 0g;
    String line;
    while ((line = reader.readLine()) != null) {
        if (line.trim().isEmpty()) continue;
        List<String> v = line.split(",", -1).collect { it.trim() };
        BigDecimal qty   = v[iQty]   as BigDecimal;
        BigDecimal price = v[iPrice] as BigDecimal;
        BigDecimal lineT = qty * price;
        grand += lineT;
        lines.add([sku: v[iSku], quantity: qty, lineTotal: lineT]);
    }

    String priority = priorityFromAmount(grand);

    StringWriter sw = new StringWriter();
    MarkupBuilder xml = new MarkupBuilder(sw);
    xml.CanonicalOrder {
        header {
            'orderId'(orderId);
            'customer'(customer);
            'currencyIso4217'(currency);
            'totalAmount'(grand);
            'priority'(priority);
        }
        'lines' {
            lines.each { l ->
                'line' {
                    'sku'(l.sku);
                    'quantity'(l.quantity);
                    'lineTotal'(l.lineTotal);
                }
            }
        }
        'totals' {
            'lineCount'(lines.size());
            'grandTotal'(grand);
        }
    }

    def messageLog = messageLogFactory?.getMessageLog(message);
    if (messageLog != null) {
        messageLog.setStringProperty("orderId", orderId);
        messageLog.addAttachmentAsString("canonical-from-csv.xml",
            sw.toString(), "application/xml");
    }

    message.setBody(sw.toString());
    return message;
}

String priorityFromAmount(BigDecimal n) {
    if (n >= 100000g) return "HIGH";
    if (n >= 10000g)  return "MEDIUM";
    return "LOW";
}
