export const process = (sourceText, sourcePath, options) => {
  return {
    code: `module.exports = \`${sourceText}\`;`,
  }
}
