from markdown.extensions import Extension
from markdown.preprocessors import Preprocessor

from typing import Any, Iterable


NAME = "nomnoml"


class NomnomlPreprocessor(Preprocessor):
    def run(self, lines: list[str]) -> list[str]:
        content = list(self.filter_block(lines))
        print(content)
        return content

    def filter_block(self, lines: Iterable[str]) -> Iterable[str]:
        nomnoml_found = False
        buffer: list[str] = []
        counter = 0

        for line in lines:
            if line.startswith(f"```{NAME}"):
                nomnoml_found = True
            elif line == "```" and nomnoml_found:
                import base64

                content = base64.b64encode("\n".join(buffer).encode()).decode()
                target = f"nomnoml-canvas-{counter}"
                counter += 1
                yield from f"""
<canvas id="{target}"></canvas>
<script>
  const canvas = document.getElementById('{target}');
  const source = '{content}';
  nomnoml.draw(canvas, atob(source));
</script>""".split(
                    "\n"
                )
                nomnoml_found = False
                buffer = []
            elif nomnoml_found:
                buffer.append(line)
            else:
                yield line


class NomnomlExtension(Extension):
    """Add source code hilighting to markdown codeblocks."""

    def extendMarkdown(self, md, md_globals):
        """Add HilitePostprocessor to Markdown instance."""
        # Insert a preprocessor before ReferencePreprocessor
        md.preprocessors.register(NomnomlPreprocessor(md), NAME, 34)

        md.registerExtension(self)


def makeExtension(**kwargs):
    return NomnomlExtension(**kwargs)
