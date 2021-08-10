pub type Err = Box<dyn std::error::Error>;
pub type Res<T> = Result<T, Err>;

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct Region {
    pub id: i64,
    pub name: String,
    pub code: String,
    pub typ: String,
}
