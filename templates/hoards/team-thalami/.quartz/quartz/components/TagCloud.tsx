import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"
import { classNames } from "../util/lang"
import { pathToRoot, joinSegments } from "../util/path"
import style from "./styles/tagCloud.scss"

const TagCloud: QuartzComponent = ({
  displayClass,
  allFiles,
  fileData,
}: QuartzComponentProps) => {
  // Count tag frequencies
  const tagCounts = new Map<string, number>()
  for (const file of allFiles) {
    for (const tag of file.frontmatter?.tags ?? []) {
      tagCounts.set(tag, (tagCounts.get(tag) ?? 0) + 1)
    }
  }

  if (tagCounts.size === 0) return null

  // Top 20 tags by frequency, then alphabetical within same count
  const top = [...tagCounts.entries()]
    .sort(([a, ca], [b, cb]) => cb - ca || a.localeCompare(b))
    .slice(0, 20)
    .sort(([a], [b]) => a.localeCompare(b))

  const maxCount = Math.max(...top.map(([, c]) => c))
  const minCount = Math.min(...top.map(([, c]) => c))
  const baseDir = pathToRoot(fileData.slug!)

  return (
    <div class={classNames(displayClass, "tag-cloud")}>
      <h3>Tags</h3>
      <div class="tag-cloud-words">
        {top.map(([tag, count]) => {
          // Scale font between 0.7rem and 1.2rem based on frequency
          const scale =
            maxCount === minCount ? 0.5 : (count - minCount) / (maxCount - minCount)
          const fontSize = 0.7 + scale * 0.5
          return (
            <a
              href={joinSegments(baseDir, "tags", tag)}
              class="tag-cloud-item"
              style={`font-size: ${fontSize}rem`}
              title={`${tag} (${count})`}
            >
              {tag}
            </a>
          )
        })}
      </div>
      {tagCounts.size > 20 && (
        <a href={joinSegments(baseDir, "tags")} class="tag-cloud-see-all">
          all {tagCounts.size} tags
        </a>
      )}
    </div>
  )
}

TagCloud.css = style

export default (() => TagCloud) satisfies QuartzComponentConstructor
