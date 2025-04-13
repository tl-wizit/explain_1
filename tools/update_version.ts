import * as fs from 'fs/promises';
import * as path from 'path';

async function updateVersion() {
    try {
        const versionFile = path.join(__dirname, '../lib/version.dart');
        
        // Read current version or start at 1
        let currentBuild = 1;
        try {
            const content = await fs.readFile(versionFile, 'utf8');
            const match = content.match(/static const int build = (\d+);/);
            if (match) {
                currentBuild = parseInt(match[1], 10) + 1;
            }
        } catch (error) {
            // File doesn't exist yet, use initial build number
            console.log('No existing version file found, starting at build 1');
        }

        // Generate new version file content
        const versionContent = `// This file is auto-generated. Do not edit manually.
class Version {
  static const String number = '1.0.0';
  static const int build = ${currentBuild};
}
`;

        // Create lib directory if it doesn't exist
        const libDir = path.join(__dirname, '../lib');
        await fs.mkdir(libDir, { recursive: true });

        // Write the new version file
        await fs.writeFile(versionFile, versionContent, 'utf8');
        console.log(`Updated build number to ${currentBuild}`);
    } catch (error) {
        console.error('Error updating version:', error);
        process.exit(1);
    }
}

// Run the async function
updateVersion();