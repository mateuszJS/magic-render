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

mod line;
mod texture;
mod types;

use std::collections::HashMap;

use gloo_utils::format::JsValueSerdeExt;
use line::Line;
use serde::{Deserialize, Serialize};
use texture::Texture;
use types::{Point, VertexPoint};
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct State {
    assets: HashMap<usize, Texture>,
    hovered_asset_id: usize, // 0 -> no asset is hovered
}

#[wasm_bindgen]
impl State {
    pub fn new(width: f32, height: f32) -> State {
        State {
            assets: HashMap::new(),
            hovered_asset_id: 0,
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

    pub fn update_hover(&mut self, id: usize) {
        self.hovered_asset_id = id
    }

    pub fn get_border(&self) -> Vec<f32> {
        if self.assets.contains_key(&self.hovered_asset_id) {
            let asset: &Texture = self.assets.get(&self.hovered_asset_id).unwrap();

            asset
                .points
                .iter()
                .enumerate()
                .flat_map(|(index, point)| {
                    Line::get_vertex_data(
                        point,
                        if index == 3 {
                            &asset.points[0]
                        } else {
                            &asset.points[index + 1]
                        },
                        20.0,
                        (1.0, 0.0, 0.0, 1.0),
                    )
                })
                .collect::<Vec<f32>>()
        } else {
            vec![]
        }
    }
}

#[derive(Serialize, Deserialize)]
struct ShaderInput {
    texture_id: usize,
    vertex_data: Vec<f32>,
}
