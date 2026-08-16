/**
 * Google Apps Script pour synchroniser l'historique des opérations Flutter.
 * Déployez comme application Web et utilisez l'URL /exec dans l'application.
 */
function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents || '{}');
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Historique');
    if (!sheet) sheet = SpreadsheetApp.getActiveSpreadsheet().insertSheet('Historique');
    var headers = ['ID', 'Date', 'Type', 'Produit', 'Code-barres', 'Quantité', 'Prix unitaire (DA)', 'Total ligne (DA)', 'Total opération (DA)', 'Devise'];
    if (sheet.getLastRow() > 1) {
      sheet.getRange(2, 1, sheet.getLastRow() - 1, sheet.getLastColumn()).clearContent();
    }
    if (sheet.getLastRow() === 0) sheet.appendRow(headers);
    (data.history || []).forEach(function(operation) {
      var items = operation.items || [];
      if (items.length === 0) {
        sheet.appendRow([operation.id || '', operation.date || '', operation.type || '', '', '', '', '', '', operation.total || 0, data.currency || 'DZD']);
      } else {
        items.forEach(function(item) {
          sheet.appendRow([
            operation.id || '', operation.date || '', operation.type || 'Vente', item.produit || '', item.codeBarres || '', item.quantite || 0,
            item.prixUnitaire || 0, item.total || 0, operation.total || 0, data.currency || 'DZD'
          ]);
        });
      }
    });
    return ContentService.createTextOutput(JSON.stringify({ok: true, count: (data.history || []).length})).setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ok: false, error: String(err)})).setMimeType(ContentService.MimeType.JSON);
  }
}
