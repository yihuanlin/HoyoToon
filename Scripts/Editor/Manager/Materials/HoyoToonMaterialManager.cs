#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using System.IO;
using System.Linq;
using Newtonsoft.Json;



namespace HoyoToon
{
    public class HoyoToonMaterialManager : Editor
    {
        #region Constants
        public static readonly string HSRShader = HoyoToonDataManager.HSRShader;
        public static readonly string GIShader = HoyoToonDataManager.GIShader;
        public static readonly string Hi3Shader = HoyoToonDataManager.Hi3Shader;
        public static readonly string HI3P2Shader = HoyoToonDataManager.HI3P2Shader;
        public static readonly string WuWaShader = HoyoToonDataManager.WuWaShader;
        public static readonly string ZZZShader = HoyoToonDataManager.ZZZShader;

        #endregion


        #region Material Generation

        [MenuItem("Assets/HoyoToon/Materials/Generate Materials", priority = 20)]
        public static void GenerateMaterialsFromJson()
        {
            HoyoToonParseManager.DetermineBodyType();
            HoyoToonDataManager.GetHoyoToonData();
            var textureCache = new Dictionary<string, Texture>();
            UnityEngine.Object[] selectedObjects = Selection.objects;
            List<string> loadedTexturePaths = new List<string>();

            foreach (var selectedObject in selectedObjects)
            {
                string selectedPath = AssetDatabase.GetAssetPath(selectedObject);

                if (Path.GetExtension(selectedPath) == ".json")
                {
                    ProcessJsonFile(selectedPath, textureCache, loadedTexturePaths);
                }
                else
                {
                    string directoryName = Path.GetDirectoryName(selectedPath);
                    string materialsFolderPath = new[] { "Materials", "Material", "Mat" }
                        .Select(folder => Path.Combine(directoryName, folder))
                        .FirstOrDefault(path => Directory.Exists(path) && Directory.GetFileSystemEntries(path).Any());

                    if (materialsFolderPath != null)
                    {
                        string[] jsonFiles = Directory.GetFiles(materialsFolderPath, "*.json");
                        foreach (string jsonFile in jsonFiles)
                        {
                            ProcessJsonFile(jsonFile, textureCache, loadedTexturePaths);
                        }
                    }
                    else
                    {
                        string validFolderNames = string.Join(", ", new[] { "Materials", "Material", "Mat" });
                        EditorUtility.DisplayDialog("Error", $"Materials folder path does not exist. Ensure your materials are in a folder named {validFolderNames}.", "OK");
                        HoyoToonLogs.ErrorDebug("Materials folder path does not exist. Ensure your materials are in a folder named 'Materials'.");
                    }
                }
            }

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
        }

        private static void ProcessJsonFile(string jsonFile, Dictionary<string, Texture> textureCache, List<string> loadedTexturePaths)
        {
            TextAsset jsonTextAsset = AssetDatabase.LoadAssetAtPath<TextAsset>(jsonFile);
            string jsonContent = jsonTextAsset.text;
            MaterialJsonStructure materialData = JsonConvert.DeserializeObject<MaterialJsonStructure>(jsonContent);
            string jsonFileName = Path.GetFileNameWithoutExtension(jsonFile);

            Shader shaderToApply = DetermineShader(materialData);

            if (shaderToApply != null)
            {
                HoyoToonLogs.LogDebug($"Final shader to apply: {shaderToApply.name}");
                string materialPath = Path.GetDirectoryName(jsonFile) + "/" + jsonFileName + ".mat";
                Material materialToUpdate = GetOrCreateMaterial(materialPath, shaderToApply, jsonFileName);

                if (materialData.IsUnityFormat)
                {
                    ProcessUnityMaterialProperties(materialData, materialToUpdate, textureCache, loadedTexturePaths, shaderToApply);
                }
                else if (materialData.IsUnrealFormat)
                {
                    ProcessUnrealMaterialProperties(materialData, materialToUpdate, textureCache, loadedTexturePaths);
                }

                HoyoToonTextureManager.SetTextureImportSettings(loadedTexturePaths);
                ApplyCustomSettingsToMaterial(materialToUpdate, jsonFileName);

                EditorUtility.SetDirty(materialToUpdate);
                AssetDatabase.SaveAssets();
                AssetDatabase.Refresh();
                ApplyScriptedSettingsToMaterial(materialToUpdate, jsonFileName, jsonFile, JObject.Parse(jsonContent));
            }
            else
            {
                EditorUtility.DisplayDialog("Error", $"No compatible shader found for {jsonFileName}. Generation shall continue.", "OK");
                HoyoToonLogs.ErrorDebug("No compatible shader found for " + jsonFileName);
            }
        }

        private static Material GetOrCreateMaterial(string materialPath, Shader shader, string materialName)
        {
            Material existingMaterial = AssetDatabase.LoadAssetAtPath<Material>(materialPath);
            if (existingMaterial != null)
            {
                existingMaterial.shader = shader;
                return existingMaterial;
            }

            Material newMaterial = new Material(shader) { name = materialName };
            AssetDatabase.CreateAsset(newMaterial, materialPath);
            return newMaterial;
        }

        private static void ProcessUnityMaterialProperties(MaterialJsonStructure materialData, Material material, 
            Dictionary<string, Texture> textureCache, List<string> loadedTexturePaths, Shader shader)
        {
            var properties = materialData.m_SavedProperties;

            // Process floats
            if (properties.m_Floats != null)
            {
                foreach (var kvp in properties.m_Floats)
                {
                    if (material.HasProperty(kvp.Key))
                    {
                        material.SetFloat(kvp.Key, kvp.Value);
                    }
                }
            }

            // Process ints
            if (properties.m_Ints != null)
            {
                foreach (var kvp in properties.m_Ints)
                {
                    if (material.HasProperty(kvp.Key))
                    {
                        material.SetInt(kvp.Key, kvp.Value);
                    }
                }
            }

            // Process colors
            if (properties.m_Colors != null)
            {
                foreach (var kvp in properties.m_Colors)
                {
                    if (material.HasProperty(kvp.Key))
                    {
                        material.SetColor(kvp.Key, kvp.Value.ToColor());
                    }
                }
            }

            // Process textures
            if (properties.m_TexEnvs != null)
            {
                foreach (var kvp in properties.m_TexEnvs)
                {
                    if (material.HasProperty(kvp.Key))
                    {
                        ProcessTextureProperty(material, kvp.Key, kvp.Value, textureCache, loadedTexturePaths, shader);
                    }
                }
            }
        }

        private static void ProcessUnrealMaterialProperties(MaterialJsonStructure materialData, Material material,
            Dictionary<string, Texture> textureCache, List<string> loadedTexturePaths)
        {
            var parameters = materialData.Parameters;

            // Process colors
            if (parameters.Colors != null)
            {
                foreach (var kvp in parameters.Colors)
                {
                    string unityPropertyName = "_" + kvp.Key;
                    if (material.HasProperty(unityPropertyName))
                    {
                        material.SetColor(unityPropertyName, kvp.Value.ToColor());
                    }
                }
            }

            // Process scalars
            if (parameters.Scalars != null)
            {
                foreach (var kvp in parameters.Scalars)
                {
                    string unityPropertyName = "_" + kvp.Key;
                    if (material.HasProperty(unityPropertyName))
                    {
                        material.SetFloat(unityPropertyName, kvp.Value);
                    }
                }
            }

            // Process switches
            if (parameters.Switches != null)
            {
                foreach (var kvp in parameters.Switches)
                {
                    string unityPropertyName = "_" + kvp.Key;
                    if (material.HasProperty(unityPropertyName))
                    {
                        material.SetInt(unityPropertyName, kvp.Value ? 1 : 0);
                    }
                }
            }

            // Process render queue
            if (parameters.RenderQueue != 0)
            {
                material.renderQueue = parameters.RenderQueue;
            }

            // Process textures
            if (materialData.Textures != null)
            {
                foreach (var kvp in materialData.Textures)
                {
                    string unityPropertyName = "_" + kvp.Key;
                    if (material.HasProperty(unityPropertyName))
                    {
                        string texturePath = kvp.Value;
                        string textureName = texturePath.Substring(texturePath.LastIndexOf('.') + 1);
                        Texture texture = FindOrLoadTexture(textureName, textureCache);
                        
                        if (texture != null)
                        {
                            material.SetTexture(unityPropertyName, texture);
                            string assetPath = AssetDatabase.GetAssetPath(texture);
                            loadedTexturePaths.Add(assetPath);

                            material.SetTextureScale(unityPropertyName, Vector2.one);
                            material.SetTextureOffset(unityPropertyName, Vector2.zero);
                        }
                    }
                }
            }
        }

        private static void ProcessTextureProperty(Material material, string propertyName, MaterialJsonStructure.TexturePropertyInfo textureInfo,
            Dictionary<string, Texture> textureCache, List<string> loadedTexturePaths, Shader shader)
        {
            string textureName = textureInfo.m_Texture.Name;

            if (string.IsNullOrEmpty(textureName))
            {
                HoyoToonTextureManager.HardsetTexture(material, propertyName, shader);
                return;
            }

            Texture texture = FindOrLoadTexture(textureName, textureCache);
            if (texture != null)
            {
                material.SetTexture(propertyName, texture);
                string texturePath = AssetDatabase.GetAssetPath(texture);
                loadedTexturePaths.Add(texturePath);

                material.SetTextureScale(propertyName, textureInfo.m_Scale.ToVector2());
                material.SetTextureOffset(propertyName, textureInfo.m_Offset.ToVector2());
            }
        }

        private static Texture FindOrLoadTexture(string textureName, Dictionary<string, Texture> textureCache)
        {
            if (textureCache.TryGetValue(textureName, out Texture texture))
            {
                return texture;
            }

                            string[] textureGUIDs = AssetDatabase.FindAssets(textureName + " t:texture");
                            if (textureGUIDs.Length > 0)
                            {
                string texturePath = AssetDatabase.GUIDToAssetPath(textureGUIDs[0]);
                texture = AssetDatabase.LoadAssetAtPath<Texture>(texturePath);
                                if (texture != null)
                                {
                                    textureCache.Add(textureName, texture);
                }
            }

            return texture;
        }

        public static void ApplyCustomSettingsToMaterial(Material material, string jsonFileName)
        {
            var shaderName = material.shader.name;
            HoyoToonLogs.LogDebug($"Shader name: {shaderName}");

            if (HoyoToonDataManager.Data.MaterialSettings.TryGetValue(shaderName, out var shaderSettings))
            {
                HoyoToonLogs.LogDebug($"Found settings for shader: {shaderName}");

                var matchedSettings = shaderSettings.FirstOrDefault(setting => jsonFileName.Contains(setting.Key)).Value
                                      ?? shaderSettings.GetValueOrDefault("Default");

                if (matchedSettings != null)
                {
                    HoyoToonLogs.LogDebug($"Matched settings found for JSON file: {jsonFileName}");

                    foreach (var property in matchedSettings)
                    {
                        try
                        {
                            var propertyValue = property.Value.ToString();

                            // Check if the property value references another property
                            if (material.HasProperty(propertyValue))
                            {
                                var referencedValue = material.GetFloat(propertyValue);
                                material.SetFloat(property.Key, referencedValue);
                                HoyoToonLogs.LogDebug($"Successfully set property: {property.Key} to {referencedValue} (referenced from {propertyValue})");
                            }
                            else
                            {
                                // Attempt to parse the property value as int or float
                                if (int.TryParse(propertyValue, out var intValue))
                                {
                                    material.SetInt(property.Key, intValue);
                                    HoyoToonLogs.LogDebug($"Successfully set int property: {property.Key} to {intValue}");
                                }
                                else if (float.TryParse(propertyValue, out var floatValue))
                                {
                                    material.SetFloat(property.Key, floatValue);
                                    HoyoToonLogs.LogDebug($"Successfully set float property: {property.Key} to {floatValue}");
                                }
                                else
                                {
                                    HoyoToonLogs.WarningDebug($"Failed to parse property: {property.Key} as int or float");
                                }
                            }
                        }
                        catch (Exception ex)
                        {
                            HoyoToonLogs.ErrorDebug($"Failed to set property: {property.Key} with value: {property.Value}. Error: {ex.Message}");
                        }
                    }

                    if (matchedSettings.TryGetValue("renderQueue", out var renderQueue))
                    {
                        try
                        {
                            material.renderQueue = Convert.ToInt32(renderQueue);
                            HoyoToonLogs.LogDebug($"Successfully set renderQueue to {renderQueue}");
                        }
                        catch (Exception ex)
                        {
                            HoyoToonLogs.ErrorDebug($"Failed to set renderQueue to {renderQueue}. Error: {ex.Message}");
                        }
                    }
                }
            }
            else
            {
                HoyoToonLogs.ErrorDebug($"No settings found for shader: {shaderName}");
            }
        }

        private static void ApplyScriptedSettingsToMaterial(Material material, string jsonFileName, string jsonFile, JObject jsonObject)
        {
            string[] materialGUIDs = AssetDatabase.FindAssets("t:material", new[] { Path.GetDirectoryName(jsonFile) });
            Dictionary<string, Material> materials = new Dictionary<string, Material>();

            foreach (string guid in materialGUIDs)
            {
                string materialPath = AssetDatabase.GUIDToAssetPath(guid);
                Material mat = AssetDatabase.LoadAssetAtPath<Material>(materialPath);
                if (mat != null)
                {
                    materials[Path.GetFileNameWithoutExtension(materialPath)] = mat;
                }
            }

            if (material.shader.name == HSRShader)
            {
                if (jsonFileName.Contains("Hair"))
                {
                    string[] faceMaterialGUIDs = AssetDatabase.FindAssets("Face t:material", new[] { Path.GetDirectoryName(jsonFile) });
                    if (faceMaterialGUIDs.Length > 0)
                    {
                        string faceMaterialPath = AssetDatabase.GUIDToAssetPath(faceMaterialGUIDs[0]);
                        Material faceMaterial = AssetDatabase.LoadAssetAtPath<Material>(faceMaterialPath);

                        if (faceMaterial != null && faceMaterial.HasProperty("_ShadowColor"))
                        {
                            Color shadowColor = faceMaterial.GetColor("_ShadowColor");
                            material.SetColor("_ShadowColor", shadowColor);
                        }
                    }
                }
            }
            else if (material.shader.name == GIShader)
            {
                if (ContainsKey(jsonObject["m_SavedProperties"]?["m_Floats"], "_DummyFixedForNormal"))
                {
                    material.SetInt("_gameVersion", 1);
                }
                else
                {
                    material.SetInt("_gameVersion", 0);
                }
            }
            else if (material.shader.name == WuWaShader)
            {
                foreach (var kvp in materials)
                {
                    string materialName = kvp.Key;
                    Material originalMaterial = kvp.Value;

                    if (materialName.EndsWith("_OL"))
                    {
                        string baseMaterialName = materialName.Substring(0, materialName.Length - 3);
                        if (materials.TryGetValue(baseMaterialName, out Material baseMaterial))
                        {
                            if (originalMaterial.HasProperty("_MainTex"))
                            {
                                Texture mainTex = originalMaterial.GetTexture("_MainTex");
                                baseMaterial.SetTexture("_OutlineTexture", mainTex);
                            }

                            if (originalMaterial.HasProperty("_OutlineWidth"))
                            {
                                float outlineWidth = originalMaterial.GetFloat("_OutlineWidth");
                                baseMaterial.SetFloat("_OutlineWidth", outlineWidth);
                            }

                            if (originalMaterial.HasProperty("_UseVertexGreen_OutlineWidth"))
                            {
                                float useVertexGreenOutlineWidth = originalMaterial.GetFloat("_UseVertexGreen_OutlineWidth");
                                baseMaterial.SetFloat("_UseVertexGreen_OutlineWidth", useVertexGreenOutlineWidth);
                            }

                            if (originalMaterial.HasProperty("_UseVertexColorB_InnerOutline"))
                            {
                                float useVertexColorBInnerOutline = originalMaterial.GetFloat("_UseVertexColorB_InnerOutline");
                                baseMaterial.SetFloat("_UseVertexColorB_InnerOutline", useVertexColorBInnerOutline);
                            }

                            if (originalMaterial.HasProperty("_OutlineColor"))
                            {
                                Color outlineColor = originalMaterial.GetColor("_OutlineColor");
                                baseMaterial.SetColor("_OutlineColor", outlineColor);
                            }

                            if (originalMaterial.HasProperty("_UseMainTex"))
                            {
                                int useMainTex = originalMaterial.GetInt("_UseMainTex");
                                baseMaterial.SetInt("_UseMainTex", useMainTex);
                            }
                        }
                    }
                    else if (materialName.EndsWith("_HET") || materialName.EndsWith("_HETA"))
                    {
                        int lengthToTrim = materialName.EndsWith("_HET") ? 4 : 5;
                        string baseMaterialName = materialName.Substring(0, materialName.Length - lengthToTrim);
                        if (materials.TryGetValue(baseMaterialName, out Material baseMaterial))
                        {
                            if (originalMaterial.HasProperty("_Mask"))
                            {
                                Texture maskTex = originalMaterial.GetTexture("_Mask");
                                baseMaterial.SetTexture("_Mask", maskTex);
                            }
                        }
                    }
                    else if (materialName.EndsWith("Bangs"))
                    {
                        string faceMaterialName = materialName.Replace("Bangs", "Face");
                        if (materials.TryGetValue(faceMaterialName, out Material faceMaterial))
                        {
                            if (faceMaterial.HasProperty("_SkinSubsurfaceColor"))
                            {
                                Color shadowColor = faceMaterial.GetColor("_SkinSubsurfaceColor");
                                originalMaterial.SetColor("_HairShadowColor", shadowColor);
                            }
                        }
                    }
                }
            }
        }

        [MenuItem("Assets/HoyoToon/Materials/Generate Jsons", priority = 21)]
        public static void GenerateJsonsFromMaterials()
        {
            Material[] selectedMaterials = Selection.GetFiltered<Material>(SelectionMode.Assets);

            foreach (Material material in selectedMaterials)
            {
                string outputPath = Path.GetDirectoryName(AssetDatabase.GetAssetPath(material));
                outputPath = Path.Combine(outputPath, material.name + ".json");
                GenerateJsonFromMaterial(material, outputPath);
            }
            AssetDatabase.Refresh();
        }

        private static void GenerateJsonFromMaterial(Material material, string outputPath)
        {
            JObject jsonObject = new JObject();
            JObject m_SavedProperties = new JObject();
            JObject m_TexEnvs = new JObject();
            JObject m_Floats = new JObject();
            JObject m_Colors = new JObject();

            jsonObject["m_Shader"] = new JObject
        {
            { "m_FileID", material.shader.GetInstanceID() },
            { "Name", material.shader.name },
            { "IsNull", false }
        };

            Shader shader = material.shader;
            int propertyCount = ShaderUtil.GetPropertyCount(shader);
            for (int i = 0; i < propertyCount; i++)
            {
                string propertyName = ShaderUtil.GetPropertyName(shader, i);
                ShaderUtil.ShaderPropertyType propertyType = ShaderUtil.GetPropertyType(shader, i);

                if (propertyName.StartsWith("m_start") || propertyName.StartsWith("m_end"))
                {
                    continue;
                }

                switch (propertyType)
                {
                    case ShaderUtil.ShaderPropertyType.TexEnv:
                        Texture texture = material.GetTexture(propertyName);
                        if (texture != null)
                        {
                            JObject textureObject = new JObject
                        {
                            { "m_Texture", new JObject { { "m_FileID", 0 }, { "m_PathID", 0 }, { "Name", texture.name }, { "IsNull", false } } },
                            { "m_Scale", new JObject { { "X", material.GetTextureScale(propertyName).x }, { "Y", material.GetTextureScale(propertyName).y } } },
                            { "m_Offset", new JObject { { "X", material.GetTextureOffset(propertyName).x }, { "Y", material.GetTextureOffset(propertyName).y } } }
                        };
                            m_TexEnvs[propertyName] = textureObject;
                        }
                        break;
                    case ShaderUtil.ShaderPropertyType.Float:
                    case ShaderUtil.ShaderPropertyType.Range:
                        float floatValue = material.GetFloat(propertyName);
                        m_Floats[propertyName] = floatValue;
                        break;
                    case ShaderUtil.ShaderPropertyType.Color:
                        Color colorValue = material.GetColor(propertyName);
                        JObject colorObject = new JObject
                    {
                        { "r", colorValue.r },
                        { "g", colorValue.g },
                        { "b", colorValue.b },
                        { "a", colorValue.a }
                    };
                        m_Colors[propertyName] = colorObject;
                        break;
                }
            }

            m_SavedProperties["m_TexEnvs"] = m_TexEnvs;
            m_SavedProperties["m_Floats"] = m_Floats;
            m_SavedProperties["m_Colors"] = m_Colors;
            jsonObject["m_SavedProperties"] = m_SavedProperties;

            string jsonContent = jsonObject.ToString(Formatting.Indented);

            File.WriteAllText(outputPath, jsonContent);
        }

        private static Shader DetermineShader(MaterialJsonStructure materialData)
        {
            // If shader is directly specified in the Unity format
            if (materialData.m_Shader?.Name != null && !string.IsNullOrEmpty(materialData.m_Shader.Name))
            {
                Shader shader = Shader.Find(materialData.m_Shader.Name);
                if (shader != null)
                {
                    HoyoToonLogs.LogDebug($"Found shader '{materialData.m_Shader.Name}' in JSON");
                    return shader;
                }
            }

            var shaderKeywords = HoyoToonDataManager.Data.ShaderKeywords;
            var shaderPaths = HoyoToonDataManager.Data.Shaders;

            // Build shader keyword mapping
            Dictionary<string, string> shaderKeys = new Dictionary<string, string>();
            foreach (var shader in shaderKeywords)
            {
                foreach (var keyword in shader.Value)
                {
                    shaderKeys[keyword] = shader.Key;
                }
            }

            // Check for shader keywords in both Unity and Unreal formats
            foreach (var shaderKey in shaderKeys)
            {
                if (materialData.IsUnityFormat)
                {
                    var properties = materialData.m_SavedProperties;
                    bool hasKeywordInTexEnvs = properties.m_TexEnvs?.ContainsKey(shaderKey.Key) ?? false;
                    bool hasKeywordInFloats = properties.m_Floats?.ContainsKey(shaderKey.Key) ?? false;

                    if (hasKeywordInTexEnvs || hasKeywordInFloats)
                    {
                        if (shaderKey.Value == "Hi3Shader")
                        {
                            // Special handling for Hi3 shaders
                            bool isPart2Shader = shaderKeywords["HI3P2Shader"].Any(keyword =>
                                (properties.m_TexEnvs?.ContainsKey(keyword) ?? false) ||
                                (properties.m_Floats?.ContainsKey(keyword) ?? false));

                            string shaderKeyToUse = isPart2Shader ? "HI3P2Shader" : "Hi3Shader";
                            return Shader.Find(shaderPaths[shaderKeyToUse][0]);
                        }
                        
                        return Shader.Find(shaderPaths[shaderKey.Value][0]);
                    }
                }
                else if (materialData.IsUnrealFormat)
                {
                    bool hasKeywordInTextures = materialData.Textures?.ContainsKey(shaderKey.Key) ?? false;
                    bool hasKeywordInScalars = materialData.Parameters?.Scalars?.ContainsKey(shaderKey.Key) ?? false;
                    bool hasKeywordInSwitches = materialData.Parameters?.Switches?.ContainsKey(shaderKey.Key) ?? false;
                    bool hasKeywordInProperties = materialData.Parameters?.Properties?.ContainsKey(shaderKey.Key) ?? false;

                    // Special check for WuWa shader which uses ShadingModel
                    if (shaderKey.Key == "ShadingModel")
                    {
                        if (materialData.Parameters?.ShadingModel != null)
                        {
                            HoyoToonLogs.LogDebug("Found WuWa shader through ShadingModel parameter");
                            return Shader.Find(shaderPaths["WuWaShader"][0]);
                        }
                    }

                    if (hasKeywordInTextures || hasKeywordInScalars || hasKeywordInSwitches || hasKeywordInProperties)
                    {
                        HoyoToonLogs.LogDebug($"Found shader through keyword: {shaderKey.Key} for shader: {shaderKey.Value}");
                        return Shader.Find(shaderPaths[shaderKey.Value][0]);
                    }
                }
            }

            return null;
        }

        private static void ProcessUnrealTexture(Material material, string propertyName, MaterialJsonStructure.TextureInfo textureInfo,
            Dictionary<string, Texture> textureCache, List<string> loadedTexturePaths)
        {
            if (string.IsNullOrEmpty(textureInfo.Name)) return;

            string textureName = textureInfo.Name.Substring(textureInfo.Name.LastIndexOf('.') + 1);
            Texture texture = FindOrLoadTexture(textureName, textureCache);
            
            if (texture != null)
            {
                material.SetTexture(propertyName, texture);
                string texturePath = AssetDatabase.GetAssetPath(texture);
                loadedTexturePaths.Add(texturePath);

                // Set default texture scale and offset for Unreal textures
                material.SetTextureScale(propertyName, Vector2.one);
                material.SetTextureOffset(propertyName, Vector2.zero);
            }
        }

        private static bool ContainsKey(JToken token, string key)
        {
            if (token is JArray array)
            {
                return array.Any(j => j["Key"].Value<string>() == key);
            }
            else if (token is JObject obj)
            {
                return obj.ContainsKey(key);
            }
            return false;
        }

        #endregion
    }
}
#endif