const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Get the list of changed files from the command line arguments
const changedFiles = process.argv.slice(2);

// Function to find all files that import a specific file
function findImportingFiles(targetFile) {
    const importingFiles = [];
    const baseDir = 'src';
    
    // Get all .sol files in the src directory
    const allFiles = execSync(`find ${baseDir} -name "*.sol"`, { encoding: 'utf8' })
        .trim()
        .split('\n');
    
    // Check each file for imports of the target file
    for (const file of allFiles) {
        const content = fs.readFileSync(file, 'utf8');
        const relativePath = path.relative(path.dirname(file), targetFile);
        
        // Check if the file imports the target file
        if (content.includes(`import { ${path.basename(targetFile, '.sol')}`) || 
            content.includes(`import "${targetFile}"`) || 
            content.includes(`import "${relativePath}"`)) {
            importingFiles.push(file);
        }
    }
    
    return importingFiles;
}

// Process all changed files and their importing files
const filesToProcess = new Set();

for (const file of changedFiles) {
    if (file.trim() && file.endsWith('.sol')) {
        filesToProcess.add(file);
        
        // Find files that import this file
        const importingFiles = findImportingFiles(file);
        for (const importingFile of importingFiles) {
            filesToProcess.add(importingFile);
        }
    }
}

// Process each file with the tag parser
for (const file of filesToProcess) {
    console.log(`Processing ${file}`);
    try {
        execSync(`node tag_parse.js ${file} --post`, { stdio: 'inherit' });
    } catch (error) {
        console.error(`Error processing ${file}: ${error.message}`);
    }
} 