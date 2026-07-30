import {usePluginData} from '@docusaurus/useGlobalData';
import styles from './styles.module.css';

type DependencyStatusData = {
  strimr: {branch: string; commit: string; upstreamBase: string};
  aetherEngine: {revision: string};
  xcode: {version: string};
};

function shortRevision(revision: string) {
  return revision.slice(0, 12);
}

export default function DependencyStatus() {
  const data = usePluginData('plinx-dependency-status') as DependencyStatusData;

  return (
    <table className={styles.table}>
      <thead>
        <tr>
          <th>Dependency</th>
          <th>Configured value</th>
          <th>Authority</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>Strimr branch</td>
          <td><code>{data.strimr.branch}</code></td>
          <td><code>config/release-dependencies.env</code></td>
        </tr>
        <tr>
          <td>Strimr exact commit</td>
          <td><code title={data.strimr.commit}>{shortRevision(data.strimr.commit)}</code></td>
          <td><code>config/release-dependencies.env</code></td>
        </tr>
        <tr>
          <td>Strimr upstream base</td>
          <td><code title={data.strimr.upstreamBase}>{shortRevision(data.strimr.upstreamBase)}</code></td>
          <td><code>config/release-dependencies.env</code></td>
        </tr>
        <tr>
          <td>AetherEngine revision</td>
          <td><code title={data.aetherEngine.revision}>{shortRevision(data.aetherEngine.revision)}</code></td>
          <td><code>PlinxApp/project.yml</code></td>
        </tr>
        <tr>
          <td>CI Xcode version</td>
          <td><code>{data.xcode.version}</code></td>
          <td><code>.xcode-version</code></td>
        </tr>
      </tbody>
    </table>
  );
}
