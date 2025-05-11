use serde::{Deserialize, Serialize};

// Define a trait for any struct that has x and y fields
pub trait HasCoords {
    fn x(&self) -> f32;
    fn y(&self) -> f32;
}

#[derive(Serialize, Deserialize)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

impl HasCoords for Point {
    fn x(&self) -> f32 {
        self.x
    }
    fn y(&self) -> f32 {
        self.y
    }
}

#[derive(Serialize, Deserialize)]
pub struct VertexPoint {
    pub x: f32,
    pub y: f32,
    pub u: f32,
    pub v: f32,
}

impl HasCoords for VertexPoint {
    fn x(&self) -> f32 {
        self.x
    }
    fn y(&self) -> f32 {
        self.y
    }
}

pub type Color = (f32, f32, f32, f32);
