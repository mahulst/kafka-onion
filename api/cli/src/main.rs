use read_topic_api::{get_client, fetch_topics};

fn main() {
    let mut client = get_client();
    let topics = fetch_topics(&mut client);

    eprintln!("{:?}", topics);
}
