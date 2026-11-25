import {usePluginData} from '@docusaurus/useGlobalData';
import styles from './styles.module.css';

type SwiftPackagePin = {
  name: string;
  url: string;
  pinKind: string;
  pin: string;
};

type DependencyStatusData = {
  strimr: {forkBase: string};
  packages: SwiftPackagePin[];
  xcode: {version: string};
};

function shortRevision(revision: string) {
  return revision.slice(0, 12);
}

function PackagePin({dependency}: {dependency: SwiftPackagePin}) {
  if (dependency.pinKind === 'revision') {
    return <code title={dependency.pin}>{shortRevision(dependency.pin)}</code>;
  }
  return <code>{dependency.pin}</code>;
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
          <td>Absorbed Strimr base (<code>wunax/strimr</code>)</td>
          <td><code title={data.strimr.forkBase}>{shortRevision(data.strimr.forkBase)}</code></td>
          <td><code>config/release-dependencies.env</code></td>
        </tr>
        {data.packages.map((dependency) => (
          <tr key={dependency.name}>
            <td>{dependency.name} {dependency.pinKind === 'revision' ? 'revision' : 'version'}</td>
            <td><PackagePin dependency={dependency} /></td>
            <td><code>PlinxApp/project.yml</code></td>
          </tr>
        ))}
        <tr>
          <td>Configured Xcode version</td>
          <td><code>{data.xcode.version}</code></td>
          <td><code>PlinxApp/project.yml</code></td>
        </tr>
      </tbody>
    </table>
  );
}
