const fs = require('fs');
const path = require('path');

const resourceName = GetCurrentResourceName();
const resourcePath = GetResourcePath(resourceName);

// Create directories on startup
setTimeout(() => {
    const dirs = ['images/clothing', 'images/props', 'images/vehicles', 'images/worldprops'];
    dirs.forEach(dir => {
        const fullPath = path.join(resourcePath, dir);
        if (!fs.existsSync(fullPath)) {
            fs.mkdirSync(fullPath, { recursive: true });
        }
    });
    console.log('[sintic-imagecapture] Ready');
}, 100);

// Handle image saving from client
RegisterNetEvent('sintic-imagecapture:saveImage');
on('sintic-imagecapture:saveImage', (imageData, category, filename) => {
    const src = global.source;

    if (!imageData) return;

    // Extract base64 data (remove data URI prefix if present)
    let base64Data = imageData;
    const match = imageData.match(/base64,(.+)/);
    if (match) {
        base64Data = match[1];
    }

    // Decode base64 to binary
    const buffer = Buffer.from(base64Data, 'base64');
    const filePath = path.join(resourcePath, 'images', category, filename);

    try {
        fs.writeFileSync(filePath, buffer);
        console.log(`[sintic-imagecapture] Saved: ${filename}`);
        emitNet('sintic-imagecapture:imageSaved', src, true, filename);
    } catch (err) {
        console.log(`[sintic-imagecapture] Failed: ${err.message}`);
        emitNet('sintic-imagecapture:imageSaved', src, false, filename);
    }
});
