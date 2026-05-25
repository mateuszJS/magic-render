export const HIGHLIGHT_PATH = `let fill = c_Color(s);
let alpha = d_distance(s);
color = vec4f(fill.rgb * alpha, alpha);`

export const SOLID_COLOR = `let fill = c_Color(s);
let alpha = d_distance(s);
color = vec4f(fill.rgb, alpha);`

// used as replacement when program has errors
export const ERROR = `let p = floor(s.uv * 0.8);
let c = (p.x+p.y) % 2.0;
let alpha = d_distance(s);
color=vec4f(c,c,c,alpha);`
