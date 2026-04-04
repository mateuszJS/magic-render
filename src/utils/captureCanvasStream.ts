
export default function captureStreamFromCanvas(canvasNode: HTMLCanvasElement) {
  const stream = canvasNode.captureStream(60)
  const recorder = new MediaRecorder(stream)

  recorder.addEventListener("dataavailable", finishCapturing)

  recorder.start()

  return () => recorder.stop()
  // returning recorder.stop and calling it outside of this function
  // cause error "Uncaught TypeError: Illegal invocation"
}

function finishCapturing(e: MediaRecorderEventMap["dataavailable"]) {
  const videoData = [e.data]
  // var blob = new Blob(videoData, { type: "video/mp4" });
  // var blob = new Blob(videoData, { type: "application/pdf" });
  const blob = new Blob(videoData, { type: "video/webm" })
  const blobURL = URL.createObjectURL(blob)
  // window.open(blobURL);

    const a = document.createElement("a")
  document.body.appendChild(a)
  a.style.display = "none"
  a.href = blobURL
  a.download = "video"
  a.click()
  window.URL.revokeObjectURL(blobURL)

  // saveDataGithub(blob);
  // saveData(blob);
  // video.src = videoURL;
  // video.play();
}

// function saveDataGithub(blob: Blob) {
//   const reader = new FileReader();
//   const out = new Blob([blob], { type: "application/pdf" });
//   reader.onload = () => {
//     if (typeof reader.result === "string") {
//       window.location.href = reader.result;
//     } else {
//       window.open(reader.result as unknown as string);
//     }
//   };
//   reader.onloadend = () => setTimeout(() => log("setLoading(false)"), 250);
//   reader.readAsDataURL(out);
// }

// function saveDataStackOverflow(blob: Blob) {
//   var reader = new FileReader();
//   const isbContentType = "video/webm";
//   reader.onload = function (e) {
//     var bdata = btoa(reader.result as string);
//     var datauri = "data:" + isbContentType + ";base64," + bdata;
//     const newWindow = window.open(datauri);
//     setTimeout(function () {
//       log("AAAAAAA");
//       if (newWindow) {
//         newWindow.document.title = "isbFilename";
//       }
//     }, 10);
//   };
//   reader.readAsBinaryString(blob);
// }

// function saveData(blob: Blob) {
//   // function saveData(blobURL: string) {

//   // https://github.com/eligrey/FileSaver.js/issues/467#issuecomment-605596975

//   // if (
//   //   /CriOS/i.test(navigator.userAgent) &&
//   //   /iphone|ipod|ipad/i.test(navigator.userAgent)
//   // ) {
//   // const blob = jsPDFInstance.output('blob')
//   const reader = new FileReader();
//   // const out = new Blob([blob], { type: "application/pdf" });
//   // const out = new Blob([blob], { type: 'video/webm' })
//   // const out = new Blob([blob], { type: 'application/pdf' })
//   reader.onload = () => {
//     log(
//       'typeof reader.result === "string": ' + typeof reader.result === "string"
//         ? "true"
//         : "false"
//     );
//     if (typeof reader.result === "string") {
//     }
//     window.location.href = reader.result as string;
//   };

//   reader.onloadend = () => setTimeout(() => log("setLoading(false)"), 250);

//   // reader.onloadend = () => setTimeout(() => log("ended"), 250);

//   // var a = document.createElement("a");
//   // document.body.appendChild(a);
//   // a.style.display = "none";
//   // a.href = blobURL;
//   // a.download = "video";

//   // reader.onload = function (e) {
//   //   log("reader.result " + reader.result);
//   //   a.href = reader.result as string;
//   //   a.download = "video.webm";
//   //   a.click();
//   // };
//   reader.readAsDataURL(blob);

//   // var reader = new FileReader();
//   // var parsedData = JSON.parse(response);
//   // var parsedResult = _base64ToArrayBuffer(parsedData[0])
//   // var blobOutput = new Blob([parsedResult], { type: 'application/pdf' });
//   // var documentLink = document.createElement('a');
//   // document.body.appendChild(documentLink);
//   // documentLink.style = "display: none";
//   // reader.onload = function (e) {
//   //     documentLink.href = reader.result;
//   //     documentLink.download = parsedData[2];
//   //     documentLink.click();
//   // }
//   // reader.readAsDataURL(blobOutput);

//   // } else { ... }

//   // var a = document.createElement("a");
//   // document.body.appendChild(a);
//   // a.style.display = "none";
//   // a.href = blobURL;
//   // a.download = "video";
//   // a.click();
//   // window.URL.revokeObjectURL(blobURL);
// }
