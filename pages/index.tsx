import Head from 'next/head'
import Link from 'next/link'
import { Card, Col, Container, Row } from 'react-bootstrap'

export default function Home(): JSX.Element {
  return (
    <div>
      <Head>
        <title>Gallformers</title>
        <link rel="icon" href="/favicon.ico" />
      </Head>

      <Container className="text-center p-5 ">
        <Row>
          <Col><h1>Welcome to Gallformers</h1></Col></Row>
        <Row>
          <Col>The place to ID and learn about galls on plants.</Col>
        </Row>
        </Container>
        <Container>
        <Row>
          <Col>
            <Card>
              <Card.Body>
                <Link href='id'>
                  <a>
                    <h3>ID a Gall &rarr;</h3>
                    <p>Try and get an ID for a gall by providing known information.</p>
                  </a>
                  </Link>
                </Card.Body>
              </Card>
          </Col>
          <Col>
            <Card>
              <Card.Body>
                <Link href="explore">
                  <a>
                    <h3>Explore &rarr;</h3>
                    <p>Explore and investigate Galls, including locating primary sources.</p>
                  </a>
                </Link>
              </Card.Body>
            </Card>
          </Col>
        </Row>
      </Container>
    </div>
  )
}

export async function getStaticProps() {
  //TODO all of this needs to go away and a better way to handle migrations that is not dependent on better-sqlite-helper is needed
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const Database = require('better-sqlite3-helper');
  const dbPath = `${process.cwd()}/prisma/gallformers.sqlite`;

  const config = {
    path: dbPath,
    readonly: false,
    fileMustExist: false,
    WAL: false,
    migrate: {
      force: true,
      table: 'migration',
      migrationPath: './migrations'
    }
  };

  // hack to force flush migrations. :(
  const hack = new Database(config);
  const colors = hack.prepare("select * from color;").all();
  console.log(`colors: ${JSON.stringify(colors, null, '  ')})`);
  hack.close();
  const DB = new Database(config);
  console.log(`Initing DB ${JSON.stringify(DB, null, '  ')}`);

  return {
    props: {
      
    }
  }
}
