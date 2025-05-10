extern crate js_sys;
extern crate serde_wasm_bindgen;
extern crate wasm_bindgen;
extern crate web_sys;

#[macro_use]
extern crate lazy_static;

macro_rules! log {
  ($( $t:tt )*) => (web_sys::console::log_1(&format!($($t)*).into()));
}

macro_rules! err {
  ($( $t:tt )*) => (web_sys::console::error_1(&format!($($t)*).into()); panic!(""));
  // there is no way to specify panci message, so we need to do console.error and then panci any value
}

//to remove and replace with util
macro_rules! angle_diff {
  ($beta:expr, $alpha:expr) => {{
    let phi = ($beta - $alpha).abs() % (2.0 * MATH_PI); // This is either the distance or 2*Math.PI - distance
    if phi > MATH_PI {
      (2.0 * MATH_PI) - phi
    } else {
      phi
    }
  }}
}

mod texture;

use std::collections::HashMap;

use gloo_utils::format::JsValueSerdeExt; // for transforming JsValue into serde
use serde::{Deserialize, Serialize};
use texture::{Texture, VertexPoint};
use wasm_bindgen::prelude::*;

// #[wasm_bindgen]
// extern "C" {
//     fn alert(s: &str);
// }

#[wasm_bindgen]
pub struct State {
    assets: HashMap<usize, Texture>,
}

#[wasm_bindgen]
impl State {
    pub fn new(width: f32, height: f32) -> State {
        State {
            assets: HashMap::new(),
        }
    }

    pub fn add_texture(&mut self, id: usize, raw_points: JsValue, texture_id: usize) {
        let serde = raw_points.into_serde();
        let points: Vec<VertexPoint> = if serde.is_ok() {
            serde.unwrap()
        } else {
            err!("add_texture received not copatible data from JS. Failed at conversion to Rust types.");
        };

        self.assets.insert(id, Texture::new(id, points, texture_id));
    }

    pub fn get_shader_input(&self, id: usize) -> JsValue {
        let asset: &Texture = if self.assets.contains_key(&id) {
            self.assets.get(&id).unwrap()
        } else {
            err!("asset with id {id} not found");
        };

        let payload = ShaderInput {
            texture_id: asset.texture_id,
            vertex_data: asset.get_vertex_data(),
        };

        serde_wasm_bindgen::to_value(&payload).unwrap()
    }

    pub fn get_shader_pick_input(&self, id: usize) -> JsValue {
        let asset: &Texture = if self.assets.contains_key(&id) {
            self.assets.get(&id).unwrap()
        } else {
            err!("asset with id {id} not found");
        };

        let payload = ShaderInput {
            texture_id: asset.texture_id,
            vertex_data: asset.get_vertex_pick_data(),
        };

        serde_wasm_bindgen::to_value(&payload).unwrap()
    }

    pub fn update_points(&mut self, id: usize, raw_points: JsValue) {
        let asset = self.assets.get_mut(&id).unwrap();

        let serde = raw_points.into_serde();
        let points: Vec<Point> = if serde.is_ok() {
            serde.unwrap()
        } else {
            err!("add_texture received not copatible data from JS. Failed at conversion to Rust types.");
        };

        asset.update_coords(points);
    }
}

#[derive(Serialize, Deserialize)]
struct Point {
    x: f32,
    y: f32,
}

#[derive(Serialize, Deserialize)]
struct ShaderInput {
    texture_id: usize,
    vertex_data: Vec<f32>,
}
