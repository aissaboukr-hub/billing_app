/**
 * Google Apps Script pour recevoir les ventes de l'application Flutter.
 * 1. Créez une feuille Google Sheets.
 * 2. Extensions > Apps Script.
 * 3. Collez ce fichier et déployez comme application Web.
 * 4. Accès : Toute personne disposant du lien.
 * 5. Copiez l'URL /exec dans Paramètres > URL Google Sheets de l'application.
 */
function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents || '{}');
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Ventes');
    if (!sheet) sheet = SpreadsheetApp.getActiveSpreadsheet().insertSheet('Ventes');
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(['Date', 'Produit', 'Code-barres', 'Quantité', 'Prix unitaire (DA)', 'Total (DA)', 'Devise']);
    }
    (data.items || []).forEach(function(item) {
      sheet.appendRow([
        data.date || new Date().toISOString(),
        item.produit || '',
        item.codeBarres || '',
        item.quantite || 0,
        item.prixUnitaire || 0,
        item.total || 0,
        data.currency || 'DZD'
      ]);
    });
    return ContentService.createTextOutput(JSON.stringify({ok: true})).setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ok: false, error: String(err)})).setMimeType(ContentService.MimeType.JSON);
  }
}
