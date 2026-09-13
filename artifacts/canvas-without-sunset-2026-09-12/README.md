# Canvas without sunset

Sunset is no longer selected for newly generated or restored missing Canvas actors. The existing random draw is retained and only a sunset outcome becomes radialTwo, preserving other material choices.

Saved sunset actors remain decodable and retain their stored parameters, geometry and placement. The shared live/export/picker renderer maps their shader to the ordinary two-color radial gradient, including the correct compositing behavior and palette variants. Label contrast uses that same effective material. The standalone material catalog and unrelated background styles remain compatible.

58 unit/render tests passed in `/tmp/nowhere-no-sunset-green.xcresult`. Regression coverage includes 200 days with ten actors each in both new-addition and restoration paths, actual Metal pixel equality between saved sunset and radialTwo on Canvas and in the picker, saved recipe stability, silhouette diversity, blur accents, confirmation states and catalog compatibility.

Before/after PNGs are actual Metal offscreen output from the dedicated iOS simulator. They are not physical-device UI captures. No phone installation was performed for this follow-up.
